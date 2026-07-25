import AppKit

/// Custom `NSWindow` subclass for Meridian.
///
/// Ensures the native macOS window tab bar is displayed even when a single document
/// is open, and supports double-clicking the empty space in the tab bar inline
/// to create a new document.
final class MeridianWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2 {
            let point = event.locationInWindow
            if isPointInTabBarEmptySpace(point) {
                NSDocumentController.shared.newDocument(nil)
                return
            }
        }
        super.sendEvent(event)
    }

    private func isPointInTabBarEmptySpace(_ point: NSPoint) -> Bool {
        guard let contentView, let frameView = contentView.superview else {
            return false
        }

        // Titlebar and Tabbar region lives above the contentView frame
        let contentHeight = contentView.frame.height
        guard point.y >= contentHeight else {
            return false
        }

        let hitView = frameView.hitTest(point)

        // Don't intercept clicks on standard window buttons or controls
        if hitView is NSButton || hitView is NSControl {
            return false
        }

        // Don't intercept clicks on existing tab items or close buttons
        var current: NSView? = hitView
        while let view = current {
            let className = String(describing: type(of: view))
            if className.contains("TabItem") || className.contains("CloseButton") || className.contains("Button") {
                return false
            }
            current = view.superview
        }

        return true
    }
}
