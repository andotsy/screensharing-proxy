import AppKit

final class RubyfierWindow: NSWindow {
    static let initialContentSize = NSSize(width: 740, height: 560)
    static let minimumContentSize = NSSize(width: 680, height: 540)

    // SwiftUI may propose smaller constraints during a new layout pass. Keep
    // the user-facing minimum intact, including during full-screen transitions.
    override var contentMinSize: NSSize {
        get { super.contentMinSize }
        set {
            super.contentMinSize = NSSize(width: max(Self.minimumContentSize.width, newValue.width),
                                         height: max(Self.minimumContentSize.height, newValue.height))
        }
    }

    override var minSize: NSSize {
        get { super.minSize }
        set {
            let minimum = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
            super.minSize = NSSize(width: max(minimum.width, newValue.width), height: max(minimum.height, newValue.height))
        }
    }
}
