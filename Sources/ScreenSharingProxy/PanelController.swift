import AppKit
import ProxyAppSupport
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {
    private let rubyfier: RubyfierModel
    private var window: NSWindow?
    init(rubyfier: RubyfierModel) { self.rubyfier = rubyfier }
    var hasVisibleContent: Bool {
        window?.isVisible == true && (window?.contentView?.bounds.width ?? 0) >= 560
    }
    var hasUsableConsoleAndMinimumSize: Bool {
        guard let window, window.contentMinSize.width >= 680, window.contentMinSize.height >= 620,
              let root = window.contentView else { return false }
        var views = [root]
        while let view = views.popLast() {
            if let text = view as? NSTextView, text.identifier?.rawValue == "rubyfierConsole" {
                return text.isSelectable && !text.isEditable && text.enclosingScrollView?.hasVerticalScroller == true
            }
            views.append(contentsOf: view.subviews)
        }
        return false
    }
    func show() {
        if window == nil {
            let content = NSHostingView(rootView: MainPanel(rubyfier: rubyfier))
            // AppKit owns these constraints. Hosting's automatic sizing otherwise
            // resets the minimum after asynchronous SwiftUI layout updates.
            content.sizingOptions = []
            let panel = RubyfierWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 680),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                 backing: .buffered, defer: false)
            panel.contentView = content
            panel.title = "Screen Sharing Rubyfier"
            panel.contentMinSize = NSSize(width: 680, height: 620)
            panel.setContentSize(NSSize(width: 740, height: 680))
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
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = sender.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 680, height: 620)).size
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
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
