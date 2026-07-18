import AppKit

/// Programmatic main menu (ARCHITECTURE §23: menus are AppKit's domain).
/// All items use standard responder-chain selectors so NSDocument,
/// NSTextView, and NSUndoManager handle them without app-level glue.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem())
        main.addItem(windowMenuItem())
        return main
    }

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Meridian")
        menu.addItem(withTitle: "About Meridian",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meridian",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return wrapped(menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "New",
                     action: #selector(NSDocumentController.newDocument(_:)),
                     keyEquivalent: "n")
        menu.addItem(withTitle: "Open…",
                     action: #selector(NSDocumentController.openDocument(_:)),
                     keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        // String selectors: these are the canonical responder-chain
        // actions NSDocument implements; their Swift-renamed forms vary
        // by SDK, the ObjC selector names do not.
        menu.addItem(withTitle: "Save…",
                     action: Selector(("saveDocument:")),
                     keyEquivalent: "s")
        let saveAs = NSMenuItem(title: "Save As…",
                                action: Selector(("saveDocumentAs:")),
                                keyEquivalent: "S")
        menu.addItem(saveAs)
        return wrapped(menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return wrapped(menu)
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        NSApplication.shared.windowsMenu = menu
        return wrapped(menu)
    }

    private static func wrapped(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
