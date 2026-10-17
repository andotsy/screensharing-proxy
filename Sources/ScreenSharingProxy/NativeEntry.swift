import AppKit
import Darwin
import ProxyAppSupport
import ProxyCore
import ServiceManagement

@main
enum NativeEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] { print("Screen Sharing Proxy \(ProxyBuild.version)"); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if arguments.count == 2, arguments[0] == "--smoke-test" {
            delegate.smokeDestination = URL(fileURLWithPath: arguments[1])
            FileHandle.standardError.write(Data("Starting native smoke app\n".utf8))
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
    private lazy var panel = PanelController(model: model)
    private var quitting = false
    var smokeDestination: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if smokeDestination != nil { FileHandle.standardError.write(Data("Application finished launching\n".utf8)) }
        installMenu()
        panel.show()
        saver.parentWindow = panel.windowForSheet
        // Earlier diagnostic alphas exposed this setting. Remove this app's old
        // registration when upgrading; diagnostics now run only on demand.
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            do { try SMAppService.mainApp.unregister() }
            catch { model.showError("Remove Screen Sharing Proxy from Login Items in System Settings to stop the old startup setting.") }
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
            FileHandle.standardError.write(Data("Collection and save finished\n".utf8))
            guard panel.hasVisibleContent, saver.presented,
                  FileManager.default.fileExists(atPath: smokeDestination.path),
                  model.collection?.report.platform == "macOS",
                  model.collection?.report.samples.count == 10 else {
                FileHandle.standardError.write(Data("Native collection/save-panel check failed.\n".utf8)); exit(1)
            }
            print("Native collection, save dialog and ZIP export passed.")
            NSApp.terminate(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard model.isBusy else { return .terminateNow }
        quitting = true
        Task { await model.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Screen Sharing Proxy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Screen Sharing Proxy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
