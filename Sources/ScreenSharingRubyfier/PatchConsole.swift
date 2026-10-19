import AppKit
import SwiftUI

struct PatchConsole: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = NSTextView()
        view.identifier = NSUserInterfaceItemIdentifier("rubyfierConsole")
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.isAutomaticLinkDetectionEnabled = false
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textColor = .labelColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel("Patching console")
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let wasAtBottom = scroll.contentView.bounds.maxY >= view.bounds.maxY - 24
        let selection = view.selectedRange()
        view.string = text
        if selection.length > 0, NSMaxRange(selection) <= view.string.utf16.count {
            view.setSelectedRange(selection)
        } else if wasAtBottom {
            view.scrollRangeToVisible(NSRange(location: view.string.utf16.count, length: 0))
        }
    }
}
