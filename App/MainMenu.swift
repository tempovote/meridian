import AppKit
import SettingsKit
import WorkspaceUI

/// Programmatic main menu (ARCHITECTURE §23: menus are AppKit's domain).
/// All items use standard responder-chain selectors so NSDocument,
/// NSTextView, and NSUndoManager handle them without app-level glue.
@MainActor
enum MainMenu {
    private static var trackedItems: [String: (item: NSMenuItem, selector: Selector)] = [:]

    static func build(settingsStore: SettingsStore? = nil) -> NSMenu {
        trackedItems.removeAll()
        let settings = settingsStore?.current.keybindings ?? .default

        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem(settings: settings))
        main.addItem(findMenuItem(settings: settings))
        main.addItem(viewMenuItem(settings: settings))
        main.addItem(windowMenuItem())
        main.addItem(helpMenuItem())

        if let settingsStore {
            settingsStore.onChange { newSettings in
                updateKeybindings(with: newSettings.keybindings)
            }
        }

        return main
    }

    static func updateKeybindings(with keybindingSettings: KeybindingSettings) {
        let registry = KeybindingRegistry(settings: keybindingSettings)
        for (actionID, entry) in trackedItems {
            let sc = registry.shortcut(for: actionID)
            let (key, modifiers) = KeybindingRegistry.parseShortcut(sc)
            entry.item.keyEquivalent = key
            entry.item.keyEquivalentModifierMask = modifiers
            CommandRegistry.updateShortcut(
                for: entry.selector,
                keyEquivalent: key.isEmpty ? nil : key,
                modifierMask: modifiers,
            )
        }
    }
}

// MARK: - App & File Menus

private extension MainMenu {
    static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Meridian")
        menu.addItem(withTitle: "About Meridian",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…",
                     action: Selector(("checkForUpdates:")),
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

    static func fileMenuItem() -> NSMenuItem {
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
        menu.addItem(.separator())
        addCommand(
            to: menu, title: "Add to Favorites",
            action: Selector(("toggleFavorite:")), keyEquivalent: "d",
        )
        return wrapped(menu)
    }
}

// MARK: - Edit & Search Menus

private extension MainMenu {
    private static func editMenuItem(settings: KeybindingSettings) -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        addBasicEditCommands(to: menu)
        menu.addItem(.separator())
        addLineEditingCommands(to: menu, settings: settings)
        menu.addItem(.separator())
        addMultiCaretCommands(to: menu)
        menu.addItem(.separator())
        addTransformCommands(to: menu, settings: settings)
        return wrapped(menu)
    }

    private static func addBasicEditCommands(to menu: NSMenu) {
        addCommand(to: menu, title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        addCommand(to: menu, title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        addCommand(to: menu, title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        addCommand(to: menu, title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        addCommand(to: menu, title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        addCommand(to: menu, title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    private static func addLineEditingCommands(to menu: NSMenu, settings: KeybindingSettings) {
        addCommand(
            to: menu, title: "Duplicate Line", action: Selector(("duplicateLine:")),
            keyEquivalent: "D", actionID: "duplicateLine", settings: settings,
        )
        addCommand(to: menu, title: "Delete Line", action: Selector(("deleteLine:")), keyEquivalent: "K")
        addCommand(
            to: menu,
            title: "Sort Lines Ascending",
            action: Selector(("sortLinesAscending:")),
            keyEquivalent: "",
        )
        addCommand(
            to: menu,
            title: "Sort Lines Descending",
            action: Selector(("sortLinesDescending:")),
            keyEquivalent: "",
        )
        addCommand(to: menu, title: "Deduplicate Lines", action: Selector(("deduplicateLines:")), keyEquivalent: "")
    }

    private static func addMultiCaretCommands(to menu: NSMenu) {
        addCommand(
            to: menu,
            title: "Add Caret Above",
            action: Selector(("addCaretAbove:")),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifierMask: [.option, .command],
        )
        addCommand(
            to: menu,
            title: "Add Caret Below",
            action: Selector(("addCaretBelow:")),
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            modifierMask: [.option, .command],
        )
        addCommand(
            to: menu,
            title: "Select Next Occurrence",
            action: Selector(("selectNextOccurrence:")),
            keyEquivalent: "d",
        )
        addCommand(
            to: menu,
            title: "Select All Occurrences",
            action: Selector(("selectAllOccurrences:")),
            keyEquivalent: "l",
            modifierMask: [.command, .shift],
        )
    }

    private static func addTransformCommands(to menu: NSMenu, settings: KeybindingSettings) {
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
        menu.addItem(.separator())
        addCommand(
            to: menu, title: "Format Document",
            action: Selector(("formatDocument:")), keyEquivalent: "I", modifierMask: [.command, .shift],
            actionID: "formatDocument", settings: settings,
        )
        addCommand(
            to: menu, title: "Minify Document",
            action: Selector(("minifyDocument:")), keyEquivalent: "",
        )
    }

    private static func findMenuItem(settings: KeybindingSettings) -> NSMenuItem {
        let menu = NSMenu(title: "Find")
        addCommand(
            to: menu, title: "Find…", action: Selector(("performFind:")),
            keyEquivalent: "f", actionID: "find", settings: settings,
        )
        addCommand(
            to: menu, title: "Find and Replace…", action: Selector(("performFindAndReplace:")),
            keyEquivalent: "f", modifierMask: [.command, .option],
        )
        addCommand(
            to: menu, title: "Find in Files…", action: Selector(("performFindInFiles:")),
            keyEquivalent: "F", modifierMask: [.command, .shift],
            actionID: "findInFiles", settings: settings,
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

    private static func viewMenuItem(settings: KeybindingSettings) -> NSMenuItem {
        let menu = NSMenu(title: "View")
        addCommand(
            to: menu, title: "Line Numbers", action: Selector(("toggleLineNumbers:")),
            keyEquivalent: "l", modifierMask: [.command, .option],
        )
        addCommand(
            to: menu, title: "Soft Wrap", action: Selector(("toggleSoftWrap:")),
            keyEquivalent: "w", modifierMask: [.command, .option],
            actionID: "toggleSoftWrap", settings: settings,
        )
        addCommand(to: menu, title: "Status Bar", action: Selector(("toggleStatusBar:")), keyEquivalent: "")
        addCommand(
            to: menu, title: "Toggle Sidebar", action: Selector(("toggleSidebar:")),
            keyEquivalent: "b", modifierMask: [.command],
        )
        addCommand(
            to: menu, title: "Markdown Preview", action: Selector(("toggleMarkdownPreview:")),
            keyEquivalent: "M", modifierMask: [.command, .shift],
            actionID: "toggleMarkdownPreview", settings: settings,
        )
        menu.addItem(.separator())
        addCommand(
            to: menu, title: "Show Tab Bar", action: Selector(("toggleTabBar:")),
            keyEquivalent: "T", modifierMask: [.command, .shift],
        )
        addCommand(
            to: menu, title: "Show All Tabs", action: Selector(("toggleTabOverview:")),
            keyEquivalent: "O", modifierMask: [.command, .shift],
        )
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
        menu.addItem(foldMenuItem(settings: settings))
        return wrapped(menu)
    }

    /// Arrow-key equivalents use `NSEvent`'s function-key constants (imported
    /// as `Int`); `UnicodeScalar`'s failable `Int` initializer is safe here
    /// since both constants are well within the valid scalar range.
    private static func foldMenuItem(settings: KeybindingSettings) -> NSMenuItem {
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
            actionID: "foldAll", settings: settings,
        )
        addCommand(
            to: foldMenu, title: "Unfold All", action: Selector(("unfoldAll:")),
            keyEquivalent: rightArrow, modifierMask: [.command, .option, .shift],
            actionID: "unfoldAll", settings: settings,
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
        actionID: String? = nil, settings: KeybindingSettings? = nil,
    ) -> NSMenuItem {
        var finalKey = keyEquivalent
        var finalModifiers = modifierMask ?? .command

        if let actionID, let settings {
            let registry = KeybindingRegistry(settings: settings)
            let sc = registry.shortcut(for: actionID)
            let (parsedKey, parsedModifiers) = KeybindingRegistry.parseShortcut(sc)
            finalKey = parsedKey
            finalModifiers = parsedModifiers
        }

        let item = NSMenuItem(title: title, action: action, keyEquivalent: finalKey)
        item.keyEquivalentModifierMask = finalModifiers
        menu.addItem(item)

        if let actionID {
            trackedItems[actionID] = (item: item, selector: action)
        }

        CommandRegistry.register(
            title: title, selector: action, keyEquivalent: finalKey.isEmpty ? nil : finalKey,
            modifierMask: finalModifiers,
        )
        return item
    }
}
