import AppKit
import ProxyAppSupport
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {
    private let model: DiagnosticsModel
    private var window: NSWindow?
    init(model: DiagnosticsModel) { self.model = model }
    var hasVisibleContent: Bool {
        window?.isVisible == true && (window?.contentView?.bounds.width ?? 0) >= 580
    }
    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: MainPanel(model: model))
            controller.sizingOptions = []
            let panel = NSWindow(contentViewController: controller)
            panel.title = "Screen Sharing Proxy"
            panel.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            panel.contentMinSize = NSSize(width: 580, height: 500)
            panel.setContentSize(NSSize(width: 600, height: 590))
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.delegate = self
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil); return false
    }
}

struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
