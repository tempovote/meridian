import AppKit
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
    public func shortcut(for actionID: String, default defaultShortcut: String = "") -> String {
        if let custom = customBindings[actionID] {
            return custom
        }
        if !defaultShortcut.isEmpty {
            return defaultShortcut
        }
        return KeybindingSettings.defaultShortcuts[actionID] ?? ""
    }

    /// Parses a shortcut string like "cmd+shift+f" into key equivalent and modifier flags for AppKit menus.
    public func keyEquivalent(for actionID: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        let sc = shortcut(for: actionID)
        return Self.parseShortcut(sc)
    }

    public static func parseShortcut(_ shortcut: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        let parts = shortcut.lowercased().components(separatedBy: "+")
        var modifiers: NSEvent.ModifierFlags = []
        var key = ""
        for part in parts {
            switch part {
            case "cmd", "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "option", "alt":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            default:
                key = part
            }
        }
        return (key, modifiers)
    }
}
