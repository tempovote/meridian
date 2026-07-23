import AppKit
import WorkspaceUI

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
        main.addItem(findMenuItem())
        main.addItem(viewMenuItem())
        main.addItem(windowMenuItem())
        main.addItem(helpMenuItem())
        return main
    }

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Meridian")
        menu.addItem(withTitle: "About Meridian",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…",
                     action: #selector(AppDelegate.showPreferences(_:)),
                     keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meridian",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return wrapped(menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        addCommand(to: menu, title: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        addCommand(
            to: menu,
            title: "Open…",
            action: #selector(NSDocumentController.openDocument(_:)),
            keyEquivalent: "o",
        )
        menu.addItem(.separator())
        addCommand(to: menu, title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addCommand(to: menu, title: "Save…", action: Selector(("saveDocument:")), keyEquivalent: "s")
        addCommand(to: menu, title: "Save As…", action: Selector(("saveDocumentAs:")), keyEquivalent: "S")
        return wrapped(menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        addCommand(to: menu, title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        addCommand(to: menu, title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        addCommand(to: menu, title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        addCommand(to: menu, title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        addCommand(to: menu, title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        addCommand(to: menu, title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        addCommand(to: menu, title: "Duplicate Line", action: Selector(("duplicateLine:")), keyEquivalent: "D")
        addCommand(to: menu, title: "Delete Line", action: Selector(("deleteLine:")), keyEquivalent: "K")
        addCommand(
            to: menu,
            title: "Trim Trailing Whitespace",
            action: Selector(("trimTrailingWhitespace:")),
            keyEquivalent: "",
        )
        addCommand(to: menu, title: "Make Upper Case", action: Selector(("makeUpperCase:")), keyEquivalent: "")
        addCommand(to: menu, title: "Make Lower Case", action: Selector(("makeLowerCase:")), keyEquivalent: "")
        addCommand(
            to: menu, title: "Convert Line Endings to LF",
            action: Selector(("convertLineEndingsToLF:")), keyEquivalent: "",
        )
        addCommand(
            to: menu, title: "Convert Line Endings to CRLF",
            action: Selector(("convertLineEndingsToCRLF:")), keyEquivalent: "",
        )

        return wrapped(menu)
    }

    private static func findMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Find")
        addCommand(to: menu, title: "Find…", action: Selector(("performFind:")), keyEquivalent: "f")
        addCommand(
            to: menu, title: "Find and Replace…", action: Selector(("performFindAndReplace:")),
            keyEquivalent: "f", modifierMask: [.command, .option],
        )
        addCommand(to: menu, title: "Find Next", action: Selector(("findNext:")), keyEquivalent: "g")
        addCommand(to: menu, title: "Find Previous", action: Selector(("findPrevious:")), keyEquivalent: "G")
        menu.addItem(.separator())
        addCommand(
            to: menu, title: "Command Palette…", action: Selector(("showCommandPalette:")),
            keyEquivalent: "p", modifierMask: [.command, .shift],
        )
        return wrapped(menu)
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        addCommand(
            to: menu, title: "Line Numbers", action: Selector(("toggleLineNumbers:")),
            keyEquivalent: "l", modifierMask: [.command, .option],
        )
        addCommand(
            to: menu, title: "Soft Wrap", action: Selector(("toggleSoftWrap:")),
            keyEquivalent: "w", modifierMask: [.command, .option],
        )
        addCommand(to: menu, title: "Status Bar", action: Selector(("toggleStatusBar:")), keyEquivalent: "")
        menu.addItem(.separator())
        addCommand(
            to: menu, title: "Split Horizontally", action: Selector(("splitHorizontally:")),
            keyEquivalent: "\\", modifierMask: [.command],
        )
        addCommand(
            to: menu, title: "Split Vertically", action: Selector(("splitVertically:")),
            keyEquivalent: "\\", modifierMask: [.command, .shift],
        )
        menu.addItem(.separator())
        menu.addItem(foldMenuItem())
        return wrapped(menu)
    }

    /// Arrow-key equivalents use `NSEvent`'s function-key constants (imported
    /// as `Int`); `UnicodeScalar`'s failable `Int` initializer is safe here
    /// since both constants are well within the valid scalar range.
    private static func foldMenuItem() -> NSMenuItem {
        let foldMenu = NSMenu(title: "Fold")
        let leftArrow = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        addCommand(
            to: foldMenu, title: "Fold Current Region", action: Selector(("foldCurrentRegion:")),
            keyEquivalent: leftArrow, modifierMask: [.command, .option],
        )
        addCommand(
            to: foldMenu, title: "Unfold Current Region", action: Selector(("unfoldCurrentRegion:")),
            keyEquivalent: rightArrow, modifierMask: [.command, .option],
        )
        foldMenu.addItem(.separator())
        addCommand(
            to: foldMenu, title: "Fold All", action: Selector(("foldAll:")),
            keyEquivalent: leftArrow, modifierMask: [.command, .option, .shift],
        )
        addCommand(
            to: foldMenu, title: "Unfold All", action: Selector(("unfoldAll:")),
            keyEquivalent: rightArrow, modifierMask: [.command, .option, .shift],
        )
        foldMenu.addItem(.separator())
        for level in 1 ... 5 {
            addCommand(
                to: foldMenu, title: "Fold Level \(level)", action: Selector(("foldLevel\(level):")),
                keyEquivalent: "\(level)", modifierMask: [.command, .control],
            )
        }
        let foldItem = NSMenuItem()
        foldItem.title = "Fold"
        foldItem.submenu = foldMenu
        return foldItem
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        NSApplication.shared.windowsMenu = menu
        return wrapped(menu)
    }

    private static func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        #if DEBUG
            menu.addItem(withTitle: "Simulate Crash (fatalError)",
                         action: #selector(AppDelegate.simulateCrash(_:)),
                         keyEquivalent: "")
        #endif
        return wrapped(menu)
    }

    private static func wrapped(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    /// Creates a menu item AND registers it in `CommandRegistry` in one
    /// call — the single source of truth that keeps the Command Palette
    /// synced with the menu. Only used for File/Edit/Find/View items
    /// (document/editing actions); the App menu and Window menu are
    /// deliberately excluded (see plan/spec Non-Goals).
    @discardableResult
    private static func addCommand(
        to menu: NSMenu, title: String, action: Selector, keyEquivalent: String,
        modifierMask: NSEvent.ModifierFlags? = nil,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let modifierMask {
            item.keyEquivalentModifierMask = modifierMask
        }
        menu.addItem(item)
        CommandRegistry.register(
            title: title, selector: action, keyEquivalent: keyEquivalent.isEmpty ? nil : keyEquivalent,
            modifierMask: item.keyEquivalentModifierMask,
        )
        return item
    }
}
