import AppKit

/// One entry in the Command Palette: a menu action, mirrored from
/// `MainMenu.swift` at menu-construction time. `selector` is sent via
/// `NSApp.sendAction(_:to:from:)` on execution — the same responder-chain
/// mechanism `NSMenuItem` already uses internally, so a palette-invoked
/// command behaves identically to clicking its menu item.
public struct Command: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let selector: Selector
    public let keyEquivalent: String?

    public init(title: String, selector: Selector, keyEquivalent: String?) {
        self.title = title
        self.selector = selector
        self.keyEquivalent = keyEquivalent
    }
}

/// Populated by `MainMenu.swift` (in the `App` target, which already
/// depends on `WorkspaceUI`) as it builds the File/Edit/Find/View menus —
/// deliberately excludes the App menu (About/Preferences/Quit) and Window
/// menu (Minimize), which aren't document/editing actions. Lives here
/// rather than in `App` because `CommandPaletteViewModel` (also in
/// `WorkspaceUI`) needs to read it directly, and a package cannot import
/// back into the executable target that depends on it.
@MainActor
public enum CommandRegistry {
    public private(set) static var commands: [Command] = []

    public static func register(title: String, selector: Selector, keyEquivalent: String?) {
        commands.append(Command(title: title, selector: selector, keyEquivalent: keyEquivalent))
    }
}
