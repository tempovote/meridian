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
        main.addItem(findMenuItem())
        main.addItem(viewMenuItem())
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
        menu.addItem(.separator())

        // Line & Transform Submenu items
        let dupLine = NSMenuItem(title: "Duplicate Line", action: Selector(("duplicateLine:")), keyEquivalent: "D")
        menu.addItem(dupLine)

        let deleteLine = NSMenuItem(title: "Delete Line", action: Selector(("deleteLine:")), keyEquivalent: "K")
        menu.addItem(deleteLine)

        let trimWhitespace = NSMenuItem(
            title: "Trim Trailing Whitespace",
            action: Selector(("trimTrailingWhitespace:")),
            keyEquivalent: "",
        )
        menu.addItem(trimWhitespace)

        let upperCase = NSMenuItem(title: "Make Upper Case", action: Selector(("makeUpperCase:")), keyEquivalent: "")
        menu.addItem(upperCase)

        let lowerCase = NSMenuItem(title: "Make Lower Case", action: Selector(("makeLowerCase:")), keyEquivalent: "")
        menu.addItem(lowerCase)

        let convertToLF = NSMenuItem(
            title: "Convert Line Endings to LF",
            action: Selector(("convertLineEndingsToLF:")),
            keyEquivalent: "",
        )
        menu.addItem(convertToLF)

        let convertToCRLF = NSMenuItem(
            title: "Convert Line Endings to CRLF",
            action: Selector(("convertLineEndingsToCRLF:")),
            keyEquivalent: "",
        )
        menu.addItem(convertToCRLF)

        return wrapped(menu)
    }

    private static func findMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Find")

        let find = NSMenuItem(title: "Find…", action: Selector(("performFind:")), keyEquivalent: "f")
        menu.addItem(find)

        let replace = NSMenuItem(
            title: "Find and Replace…",
            action: Selector(("performFindAndReplace:")),
            keyEquivalent: "f",
        )
        replace.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(replace)

        let findNext = NSMenuItem(title: "Find Next", action: Selector(("findNext:")), keyEquivalent: "g")
        menu.addItem(findNext)

        let findPrev = NSMenuItem(title: "Find Previous", action: Selector(("findPrevious:")), keyEquivalent: "G")
        menu.addItem(findPrev)

        return wrapped(menu)
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")

        let lineNumbers = NSMenuItem(
            title: "Line Numbers",
            action: Selector(("toggleLineNumbers:")),
            keyEquivalent: "l",
        )
        lineNumbers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(lineNumbers)

        let softWrap = NSMenuItem(
            title: "Soft Wrap",
            action: Selector(("toggleSoftWrap:")),
            keyEquivalent: "w",
        )
        softWrap.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(softWrap)

        let statusBar = NSMenuItem(
            title: "Status Bar",
            action: Selector(("toggleStatusBar:")),
            keyEquivalent: "",
        )
        menu.addItem(statusBar)

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
