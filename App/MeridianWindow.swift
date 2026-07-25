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
            // After the tab bar is visible, inject the sidebar button into it.
            DispatchQueue.main.async { [weak self] in
                self?.injectSidebarButtonIntoTabBar()
            }
        }
    }

    private func injectSidebarButtonIntoTabBar() {
        // Walk up from contentView to find the "frame view" (NSThemeFrame)
        guard let frameView = contentView?.superview else { return }
        // Find the tab bar view by class name heuristic
        let tabBarView = findTabBarView(in: frameView)
        guard let tabBarView else { return }

        // Don't inject twice
        if tabBarView.subviews.contains(where: { $0.identifier?.rawValue == "meridian.sidebarTabBtn" }) {
            return
        }

        let btn = NSButton(frame: .zero)
        btn.identifier = NSUserInterfaceItemIdentifier("meridian.sidebarTabBtn")
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        btn.contentTintColor = .secondaryLabelColor
        btn.target = self
        btn.action = #selector(toggleSidebar(_:))
        btn.toolTip = "Toggle Sidebar (⌘B)"
        btn.sizeToFit()

        // Position at the leading edge of the tab bar
        let btnW: CGFloat = 32
        let btnH = tabBarView.frame.height
        btn.frame = NSRect(x: 0, y: 0, width: btnW, height: btnH)
        btn.autoresizingMask = [.minYMargin]

        tabBarView.addSubview(btn)
    }

    private func findTabBarView(in view: NSView) -> NSView? {
        let name = String(describing: type(of: view))
        // macOS internal class is "NSTabBarView" or similar
        if name.contains("TabBar") {
            return view
        }
        for sub in view.subviews {
            if let found = findTabBarView(in: sub) {
                return found
            }
        }
        return nil
    }

    @objc func toggleSidebar(_ sender: Any?) {
        if let doc = windowController?.document as? MeridianDocument {
            doc.toggleSidebar(sender)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            if let doc = windowController?.document as? MeridianDocument {
                menuItem.state = doc.isSidebarVisible ? .on : .off
                return true
            }
            return true
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
