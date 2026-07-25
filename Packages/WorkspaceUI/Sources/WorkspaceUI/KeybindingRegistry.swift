import Foundation
import SettingsKit

/// Registry for user-customized keybindings and shortcut resolution.
public final class KeybindingRegistry: Sendable {
    private let customBindings: [String: String]

    public init(settings: KeybindingSettings = .default) {
        customBindings = settings.customBindings
    }

    /// Resolves the shortcut string for a specified action identifier.
    /// Returns custom binding if configured, otherwise falls back to `defaultShortcut`.
    public func shortcut(for actionID: String, default defaultShortcut: String) -> String {
        customBindings[actionID] ?? defaultShortcut
    }
}
