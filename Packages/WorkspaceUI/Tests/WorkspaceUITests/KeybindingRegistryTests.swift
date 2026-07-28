import Foundation
import SettingsKit
import Testing
@testable import WorkspaceUI

@Suite("KeybindingRegistryTests")
struct KeybindingRegistryTests {
    @Test func resolvesDefaultShortcutWhenNoCustomBinding() {
        let registry = KeybindingRegistry()
        let shortcut = registry.shortcut(for: "findInFiles", default: "cmd+shift+f")
        #expect(shortcut == "cmd+shift+f")
    }

    @Test func resolvesCustomShortcutWhenConfigured() {
        let settings = KeybindingSettings(customBindings: ["findInFiles": "cmd+option+f"])
        let registry = KeybindingRegistry(settings: settings)
        let shortcut = registry.shortcut(for: "findInFiles", default: "cmd+shift+f")
        #expect(shortcut == "cmd+option+f")
    }

    @Test func parsesKeyEquivalentAndModifiers() {
        let (key, modifiers) = KeybindingRegistry.parseShortcut("cmd+shift+f")
        #expect(key == "F")
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.shift))

        let (noShiftKey, noShiftModifiers) = KeybindingRegistry.parseShortcut("cmd+f")
        #expect(noShiftKey == "f")
        #expect(noShiftModifiers.contains(.command))
        #expect(!noShiftModifiers.contains(.shift))
    }

    @Test func resolvesDefaultShortcutsFromSettingsKit() {
        let registry = KeybindingRegistry()
        #expect(registry.shortcut(for: "formatDocument") == "cmd+shift+i")
    }

    /// `MainMenu.addCommand` passes an explicit `keyEquivalent`/`modifierMask`
    /// for these three items, but when `actionID`/`settings` are also
    /// supplied it unconditionally overwrites both with
    /// `KeybindingRegistry.shortcut(for:)`'s result — called with no
    /// `default:`, so a missing `defaultShortcuts` entry silently erases the
    /// menu item's shortcut instead of falling back to it. All three actions
    /// went unbound and un-displayed in the View menu until this was added.
    @Test func toggleTerminalHexInspectorAndMinimapHaveDefaultShortcuts() {
        let registry = KeybindingRegistry()
        #expect(!registry.shortcut(for: "toggleTerminal").isEmpty)
        #expect(!registry.shortcut(for: "toggleHexView").isEmpty)
        #expect(!registry.shortcut(for: "toggleMinimap").isEmpty)
    }

    /// Pins the specific bindings `MainMenu.swift` was built around, not just
    /// "non-empty" — a wrong-but-nonempty value would still be a regression.
    @Test func toggleTerminalHexInspectorAndMinimapResolveToTheirOriginalBindings() {
        let registry = KeybindingRegistry()
        #expect(registry.shortcut(for: "toggleTerminal") == "ctrl+`")
        #expect(registry.shortcut(for: "toggleHexView") == "cmd+option+h")
        #expect(registry.shortcut(for: "toggleMinimap") == "cmd+option+m")
    }
}
