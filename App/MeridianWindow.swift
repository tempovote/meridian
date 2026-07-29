import AppKit

/// Custom `NSWindow` subclass for Meridian.
///
/// Ensures the native macOS window tab bar is displayed even when a single document
/// is open.
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
}
