import AppKit

/// Custom `NSWindow` subclass for Meridian.
///
/// Ensures the native macOS window tab bar is displayed even when a single document
/// is open, and supports double-clicking the empty space in the tab bar inline
/// to create a new document.
final class MeridianWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        tabbingMode = .preferred
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        ensureTabBarVisible()
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        ensureTabBarVisible()
    }

    private func ensureTabBarVisible() {
        tabbingMode = .preferred
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if tabGroup?.isTabBarVisible != true {
                toggleTabBar(nil)
            }
        }
    }

    @objc func toggleSidebar(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleSidebar(sender)
        }
    }

    @objc func formatDocument(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.formatDocument(sender)
        }
    }

    @objc func minifyDocument(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.minifyDocument(sender)
        }
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleMarkdownPreview(sender)
        }
    }

    @objc func compareWithFile(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.compareWithFile(sender)
        }
    }

    @objc func toggleHexView(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleHexView(sender)
        }
    }

    @objc func toggleMinimap(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleMinimap(sender)
        }
    }

    @objc func toggleTerminal(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleTerminal(sender)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let doc = windowController?.document as? MeridianDocument {
            return doc.validateMenuItem(menuItem)
        }
        return super.validateMenuItem(menuItem)
    }

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

        let contentTop = contentView.frame.origin.y + contentView.frame.height
        guard point.y >= contentTop - 2 else {
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
            let isTabOrButton = className.contains("TabItem") || className.contains("CloseButton")
                || className.contains("Button") || className.contains("ItemView")
            if isTabOrButton {
                return false
            }
            current = view.superview
        }

        return true
    }
}
