import AppKit
import Darwin
import ProxyAppSupport
import ProxyCore

@main
enum NativeEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] { print("Screen Sharing Rubyfier \(ProxyBuild.version)"); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if arguments.count == 2, arguments[0] == "--smoke-test" {
            delegate.smokeDestination = URL(fileURLWithPath: arguments[1])
            FileHandle.standardError.write(Data("Starting native smoke app\n".utf8))
        }
        if arguments.count == 2, arguments[0] == "--patch-smoke-test" {
            delegate.patchSmokeDirectory = URL(fileURLWithPath: arguments[1])
        }
        if arguments.count == 4, arguments[0] == "--relay-smoke-test",
           let listener = UInt16(arguments[2]), listener >= 1024,
           let media = UInt16(arguments[3]), (1024...65533).contains(media) {
            delegate.relaySmoke = (URL(fileURLWithPath: arguments[1]), listener, media)
        }
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let saver = ArchiveSavePanel()
    private lazy var model = DiagnosticsModel(saver: saver)
    private let relaySaver = ArchiveSavePanel(sessionReport: true)
    private lazy var relay = RelayModel(saver: relaySaver, launcher: relaySmoke == nil ? ScreenSharingLauncher() : SmokeViewerLauncher())
    private let rubyfier = RubyfierModel()
    private lazy var panel = PanelController(model: model, relay: relay, rubyfier: rubyfier)
    private var quitting = false
    var smokeDestination: URL?
    var patchSmokeDirectory: URL?
    var relaySmoke: (destination: URL, listener: UInt16, media: UInt16)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if smokeDestination != nil { FileHandle.standardError.write(Data("Application finished launching\n".utf8)) }
        installMenu()
        panel.show()
        saver.parentWindow = panel.windowForSheet
        relaySaver.parentWindow = panel.windowForSheet
        if let patchSmokeDirectory {
            rubyfier.create(in: patchSmokeDirectory)
            Task {
                await rubyfier.waitForCompletion()
                try? await Task.sleep(for: .milliseconds(100))
                print("Patch smoke: created=\(rubyfier.createdApp != nil), visible=\(panel.hasVisibleContent), consoleAndMinimum=\(panel.hasUsableConsoleAndMinimumSize)")
                guard let app = rubyfier.createdApp, panel.hasVisibleContent,
                      panel.hasUsableConsoleAndMinimumSize,
                      rubyfier.consoleText.contains("Verified the app signature") else {
                    FileHandle.standardError.write(Data(rubyfier.consoleText.utf8))
                    exit(1)
                }
                let result = await BoundedCommandRunner().run(CommandSpec(
                    app.appendingPathComponent("Contents/MacOS/RubiedLauncher").path,
                    ["--rubied-self-test"], timeout: 25))
                let text = String(decoding: result.errorOutput, as: UTF8.self)
                guard result.complete, text.contains("nativeUILaunched=1"),
                      text.contains("originalAddressPreserved=1"),
                      text.contains("connectedMediaSocketDictionaries=3"),
                      text.contains("nativeSocketConflictRefused=1"),
                      text.contains("tcpAndThreeNativeUDPChannels=1") else {
                    FileHandle.standardError.write(result.errorOutput)
                    exit(1)
                }
                print("Rubyfier: patch, console, window minimum, signature, injected native UI, TCP and three bidirectional native UDP channels passed.")
                NSApp.terminate(nil)
            }
            return
        }
        if let relaySmoke {
            relay.remoteAddress = "192.0.2.1" // Route selection only; no connection or packets sent.
            relay.listenerPort = Int(relaySmoke.listener); relay.mediaBase = Int(relaySmoke.media)
            relay.connect()
            Task {
                for _ in 0..<100 {
                    if relay.activity != .starting { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard panel.hasVisibleContent, relay.activity == .listening else { exit(1) }
                await relay.stop()
                guard !relay.isRunning, relay.report?.relayStopAcknowledged == true,
                      let data = try? relay.report?.json() else { exit(1) }
                do { try PrivateReportWriter.write(data, to: relaySmoke.destination, replaceExisting: false) }
                catch { exit(1) }
                print("Native proxy readiness, stop, report and child cleanup passed.")
                NSApp.terminate(nil)
            }
            return
        }
        guard let smokeDestination else { return }
        saver.smokeDestination = smokeDestination
        model.collect()
        FileHandle.standardError.write(Data("Collection started\n".utf8))
        Task {
            try? await Task.sleep(for: .seconds(60))
            FileHandle.standardError.write(Data("Native smoke watchdog: activity=\(model.activity), savePanelPresented=\(saver.presented)\n".utf8))
            exit(1)
        }
        Task {
            await model.waitForCompletion()
            FileHandle.standardError.write(Data("Collection and save-dialog cancellation finished\n".utf8))
            guard panel.hasVisibleContent, saver.presented, saver.smokePanelWasVisible,
                  model.message?.hasPrefix("Not saved.") == true,
                  model.collection?.report.platform == "macOS",
                  model.collection?.report.samples.count == 10, let archive = model.archiveData else {
                FileHandle.standardError.write(Data("Native collection/save-panel check failed.\n".utf8)); exit(1)
            }
            // Test the shared writer directly: AppKit requires a real user or
            // accessibility-driven UI test to confirm a save, not panel.ok(_:).
            do { try PrivateReportWriter.write(archive, to: smokeDestination, replaceExisting: false) }
            catch { FileHandle.standardError.write(Data("Native ZIP write failed.\n".utf8)); exit(1) }
            print("Native collection, save dialog cancellation and ZIP write passed.")
            NSApp.terminate(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard model.isBusy || relay.isRunning || relay.saving || rubyfier.isBusy else { return .terminateNow }
        quitting = true
        rubyfier.cancel()
        Task { await rubyfier.waitForCompletion(); await relay.stop(); await model.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Screen Sharing Rubyfier", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Screen Sharing Rubyfier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu; menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }
}
