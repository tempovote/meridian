import AppKit

/// Programmatic toolbar construction (sibling to `MainMenu`, same
/// stateless-builder pattern). Item enablement is driven separately by
/// `MeridianDocument`'s `NSToolbarItemValidation` conformance — this type
/// only builds items and identifier lists.
enum ToolbarBuilder {
    static let identifier = NSToolbar.Identifier("MeridianDocumentToolbar")

    static func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: identifier)
        toolbar.displayMode = .iconOnly
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = [
        .fileGroup, .editGroup, .findGroup, .formatGroup, .markdownGroup,
    ]

    /// Default items plus the long-tail Markdown items a user can opt into
    /// via right-click → "Customize Toolbar…" — not shown by default.
    static let allowedItemIdentifiers: [NSToolbarItem.Identifier] = [
        .fileGroup, .editGroup, .findGroup, .formatGroup, .markdownGroup,
        .markdownOrderedList, .markdownBlockquote, .markdownStrikethrough,
        .markdownHorizontalRule, .markdownTable, .markdownPreview, .terminal,
    ]

    static func item(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .fileGroup: fileGroup()
        case .editGroup: editGroup()
        case .findGroup: findGroup()
        case .formatGroup: formatGroup()
        case .markdownGroup: markdownGroup()
        default: leafItem(for: identifier)
        }
    }

    private static func leafItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .markdownOrderedList:
            leaf(
                .markdownOrderedList,
                label: "Ordered List",
                symbol: "list.number",
                action: Selector(("insertMarkdownOrderedList:")),
            )
        case .markdownBlockquote:
            leaf(
                .markdownBlockquote,
                label: "Blockquote",
                symbol: "text.quote",
                action: Selector(("insertMarkdownBlockquote:")),
            )
        case .markdownStrikethrough:
            leaf(
                .markdownStrikethrough,
                label: "Strikethrough",
                symbol: "strikethrough",
                action: Selector(("insertMarkdownStrikethrough:")),
            )
        case .markdownHorizontalRule:
            leaf(
                .markdownHorizontalRule,
                label: "Horizontal Rule",
                symbol: "minus",
                action: Selector(("insertMarkdownHorizontalRule:")),
            )
        case .markdownTable:
            leaf(.markdownTable, label: "Table", symbol: "tablecells", action: Selector(("insertMarkdownTable:")))
        case .markdownPreview:
            leaf(
                .markdownPreview,
                label: "Markdown Preview",
                symbol: "doc.richtext",
                action: Selector(("toggleMarkdownPreview:")),
            )
        case .terminal:
            leaf(.terminal, label: "Terminal", symbol: "terminal", action: Selector(("toggleTerminal:")))
        default:
            nil
        }
    }

    private static func leaf(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        symbol: String,
        action: Selector,
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.action = action
        return item
    }

    private static func group(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        subitems: [NSToolbarItem],
    ) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.label = label
        group.paletteLabel = label
        group.controlRepresentation = .expanded
        group.selectionMode = .momentary
        group.subitems = subitems
        return group
    }

    private static func fileGroup() -> NSToolbarItemGroup {
        group(.fileGroup, label: "File", subitems: [
            leaf(
                .newDocument,
                label: "New",
                symbol: "doc.badge.plus",
                action: #selector(NSDocumentController.newDocument(_:)),
            ),
            leaf(
                .openDocument,
                label: "Open",
                symbol: "folder",
                action: #selector(NSDocumentController.openDocument(_:)),
            ),
            leaf(.saveDocument, label: "Save", symbol: "square.and.arrow.down", action: Selector(("saveDocument:"))),
        ])
    }

    private static func editGroup() -> NSToolbarItemGroup {
        group(.editGroup, label: "Edit", subitems: [
            leaf(.undo, label: "Undo", symbol: "arrow.uturn.backward", action: Selector(("undo:"))),
            leaf(.redo, label: "Redo", symbol: "arrow.uturn.forward", action: Selector(("redo:"))),
            leaf(.cut, label: "Cut", symbol: "scissors", action: #selector(NSText.cut(_:))),
            leaf(.copy, label: "Copy", symbol: "doc.on.doc", action: #selector(NSText.copy(_:))),
            leaf(.paste, label: "Paste", symbol: "doc.on.clipboard", action: #selector(NSText.paste(_:))),
        ])
    }

    private static func findGroup() -> NSToolbarItemGroup {
        group(.findGroup, label: "Find", subitems: [
            leaf(.find, label: "Find", symbol: "magnifyingglass", action: Selector(("performFind:"))),
            leaf(
                .findAndReplace,
                label: "Find & Replace",
                symbol: "doc.text.magnifyingglass",
                action: Selector(("performFindAndReplace:")),
            ),
        ])
    }

    private static func formatGroup() -> NSToolbarItemGroup {
        group(.formatGroup, label: "Format", subitems: [
            leaf(.formatDocument, label: "Format", symbol: "textformat", action: Selector(("formatDocument:"))),
            leaf(.upperCase, label: "UPPER", symbol: "character.cursor.ibeam", action: Selector(("makeUpperCase:"))),
            leaf(.lowerCase, label: "lower", symbol: "character", action: Selector(("makeLowerCase:"))),
            leaf(
                .trimWhitespace,
                label: "Trim Whitespace",
                symbol: "eraser",
                action: Selector(("trimTrailingWhitespace:")),
            ),
        ])
    }

    private static func markdownGroup() -> NSToolbarItemGroup {
        group(.markdownGroup, label: "Markdown", subitems: [
            leaf(.markdownBold, label: "Bold", symbol: "bold", action: Selector(("insertMarkdownBold:"))),
            leaf(.markdownItalic, label: "Italic", symbol: "italic", action: Selector(("insertMarkdownItalic:"))),
            markdownHeadingItem(),
            leaf(.markdownLink, label: "Link", symbol: "link", action: Selector(("insertMarkdownLink:"))),
            leaf(.markdownList, label: "List", symbol: "list.bullet", action: Selector(("insertMarkdownList:"))),
            leaf(
                .markdownCode,
                label: "Code",
                symbol: "chevron.left.forwardslash.chevron.right",
                action: Selector(("insertMarkdownCode:")),
            ),
        ])
    }

    /// Clicking the button body inserts an H1; the dropdown arrow offers
    /// H1/H2/H3 explicitly.
    private static func markdownHeadingItem() -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: .markdownHeading)
        item.label = "Heading"
        item.paletteLabel = "Heading"
        item.toolTip = "Heading"
        item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading")
        item.isBordered = true
        item.action = Selector(("insertMarkdownHeading1:"))

        let menu = NSMenu()
        menu.addItem(withTitle: "Heading 1", action: Selector(("insertMarkdownHeading1:")), keyEquivalent: "")
        menu.addItem(withTitle: "Heading 2", action: Selector(("insertMarkdownHeading2:")), keyEquivalent: "")
        menu.addItem(withTitle: "Heading 3", action: Selector(("insertMarkdownHeading3:")), keyEquivalent: "")
        item.menu = menu

        return item
    }
}

extension NSToolbarItem.Identifier {
    static let fileGroup = NSToolbarItem.Identifier("fileGroup")
    static let editGroup = NSToolbarItem.Identifier("editGroup")
    static let findGroup = NSToolbarItem.Identifier("findGroup")
    static let formatGroup = NSToolbarItem.Identifier("formatGroup")
    static let markdownGroup = NSToolbarItem.Identifier("markdownGroup")

    static let newDocument = NSToolbarItem.Identifier("newDocument")
    static let openDocument = NSToolbarItem.Identifier("openDocument")
    static let saveDocument = NSToolbarItem.Identifier("saveDocument")
    static let undo = NSToolbarItem.Identifier("undo")
    static let redo = NSToolbarItem.Identifier("redo")
    static let cut = NSToolbarItem.Identifier("cut")
    static let copy = NSToolbarItem.Identifier("copy")
    static let paste = NSToolbarItem.Identifier("paste")
    static let find = NSToolbarItem.Identifier("find")
    static let findAndReplace = NSToolbarItem.Identifier("findAndReplace")
    static let formatDocument = NSToolbarItem.Identifier("formatDocument")
    static let upperCase = NSToolbarItem.Identifier("upperCase")
    static let lowerCase = NSToolbarItem.Identifier("lowerCase")
    static let trimWhitespace = NSToolbarItem.Identifier("trimWhitespace")

    static let markdownBold = NSToolbarItem.Identifier("markdownBold")
    static let markdownItalic = NSToolbarItem.Identifier("markdownItalic")
    static let markdownHeading = NSToolbarItem.Identifier("markdownHeading")
    static let markdownLink = NSToolbarItem.Identifier("markdownLink")
    static let markdownList = NSToolbarItem.Identifier("markdownList")
    static let markdownCode = NSToolbarItem.Identifier("markdownCode")
    static let markdownOrderedList = NSToolbarItem.Identifier("markdownOrderedList")
    static let markdownBlockquote = NSToolbarItem.Identifier("markdownBlockquote")
    static let markdownStrikethrough = NSToolbarItem.Identifier("markdownStrikethrough")
    static let markdownHorizontalRule = NSToolbarItem.Identifier("markdownHorizontalRule")
    static let markdownTable = NSToolbarItem.Identifier("markdownTable")

    static let markdownPreview = NSToolbarItem.Identifier("markdownPreview")
    static let terminal = NSToolbarItem.Identifier("terminal")
}
