import AppKit

final class RubyfierWindow: NSWindow {
    // SwiftUI may propose smaller constraints during a new layout pass. Keep
    // the user-facing minimum intact, including during full-screen transitions.
    override var contentMinSize: NSSize {
        get { super.contentMinSize }
        set { super.contentMinSize = NSSize(width: max(680, newValue.width), height: max(620, newValue.height)) }
    }

    override var minSize: NSSize {
        get { super.minSize }
        set {
            let minimum = frameRect(forContentRect: NSRect(x: 0, y: 0, width: 680, height: 620)).size
            super.minSize = NSSize(width: max(minimum.width, newValue.width), height: max(minimum.height, newValue.height))
        }
    }
}
