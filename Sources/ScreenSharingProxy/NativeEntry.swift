import AppKit
import Darwin
import ProxyAppSupport
import ProxyCore
import SwiftUI

@main
enum NativeEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] { print("Screen Sharing Proxy \(ProxyBuild.version)"); return }
        if arguments.count == 2, arguments[0] == "--smoke-test" {
            runSmokeTest(output: arguments[1]); return
        }
        NativeProxyApp.main()
    }

    private static func runSmokeTest(output: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = DiagnosticsModel()
        let panel = PanelController(model: model)
        panel.show()
        model.discover()
        Task {
            await model.waitForCompletion()
            guard panel.hasVisibleContent, let data = model.reportData,
                  model.collection?.report.platform == "macOS",
                  model.collection?.report.probes.isEmpty == false else {
                FileHandle.standardError.write(Data("Native app smoke check failed.\n".utf8))
                exit(1)
            }
            do {
                try PrivateReportWriter.write(data, to: URL(fileURLWithPath: output))
                print("Native window and automatic discovery passed.")
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Native app report export failed.\n".utf8))
                exit(1)
            }
        }
        app.run()
    }
}

struct NativeProxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            Button("Open Screen Sharing Proxy…") { AppSession.shared.panel.show() }
            Divider()
            Button("Find Allowed Service") { AppSession.shared.model.discover() }
                .disabled(AppSession.shared.model.isBusy)
            Button("Collect Diagnostics") {
                AppSession.shared.panel.show()
                AppSession.shared.model.collect()
            }.disabled(AppSession.shared.model.isBusy)
            Divider()
            Button("About Screen Sharing Proxy") { NSApp.orderFrontStandardAboutPanel(nil) }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .accessibilityLabel("Screen Sharing Proxy")
                .help("Screen Sharing Proxy — service discovery and diagnostics")
        }
    }
}

final class AppSession {
    static let shared = AppSession()
    let model = DiagnosticsModel()
    lazy var panel = PanelController(model: model)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        if !Self.launchedAtLogin { AppSession.shared.panel.show() }
        AppSession.shared.model.discover()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppSession.shared.panel.show(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard AppSession.shared.model.isBusy else { return .terminateNow }
        quitting = true
        Task {
            await AppSession.shared.model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == 0x6f617070 else { return false }
        return event.paramDescriptor(forKeyword: 0x70726474)?.enumCodeValue == 0x6c676974
    }
}
