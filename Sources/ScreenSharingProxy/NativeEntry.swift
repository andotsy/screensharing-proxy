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
            delegate.smokeMarker = URL(fileURLWithPath: arguments[1])
        }
        if arguments.count == 2, arguments[0] == "--patch-smoke-test" {
            delegate.patchSmokeDirectory = URL(fileURLWithPath: arguments[1])
        }
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let rubyfier = RubyfierModel()
    private lazy var panel = PanelController(rubyfier: rubyfier)
    private var quitting = false
    var smokeMarker: URL?
    var patchSmokeDirectory: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        panel.show()
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
        guard let smokeMarker else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            // The packaged-guide check opens the app through LaunchServices and
            // only sees this marker, so write it after the window is usable.
            guard panel.hasVisibleContent, panel.hasUsableConsoleAndMinimumSize, rubyfier.payloadAvailable,
                  (try? Data("Screen Sharing Rubyfier \(ProxyBuild.version) window ready\n".utf8)
                    .write(to: smokeMarker, options: .withoutOverwriting)) != nil else {
                FileHandle.standardError.write(Data("Native window smoke check failed.\n".utf8)); exit(1)
            }
            print("Native window, console, minimum size and bundled patcher passed.")
            NSApp.terminate(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard rubyfier.isBusy else { return .terminateNow }
        quitting = true
        rubyfier.cancel()
        Task { await rubyfier.waitForCompletion(); sender.reply(toApplicationShouldTerminate: true) }
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
