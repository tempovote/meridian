import AppKit
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

    /// An empty custom binding unbinds the action rather than restoring the
    /// default — and `PreferencesViewModel.setShortcut` disagrees: given an
    /// empty shortcut it *removes* the key, which makes the default apply.
    /// The UI therefore never writes an empty string, so this state is only
    /// reachable by hand-editing `settings.json`, where the two components
    /// give the same input opposite meanings. Pinned rather than changed:
    /// picking a winner is a product decision, and changing the registry
    /// would silently alter shortcut resolution for anyone already relying
    /// on it.
    @Test func emptyCustomBindingUnbindsRatherThanRestoringTheDefault() {
        let registry = KeybindingRegistry(
            settings: KeybindingSettings(customBindings: ["find": ""]),
        )
        #expect(registry.shortcut(for: "find").isEmpty)
        #expect(KeybindingSettings.defaultShortcuts["find"] == "cmd+f")
    }

    /// An explicitly supplied default loses to an empty custom binding too,
    /// for the same reason — the custom lookup wins before it is inspected.
    @Test func emptyCustomBindingAlsoBeatsAnExplicitlySuppliedDefault() {
        let registry = KeybindingRegistry(
            settings: KeybindingSettings(customBindings: ["find": ""]),
        )
        #expect(registry.shortcut(for: "find", default: "cmd+k").isEmpty)
    }

    @Test func unknownActionReturnsTheSuppliedDefault() {
        let registry = KeybindingRegistry()
        #expect(registry.shortcut(for: "no.such.action", default: "cmd+q") == "cmd+q")
    }

    @Test func unknownActionWithNoDefaultReturnsEmpty() {
        let registry = KeybindingRegistry()
        #expect(registry.shortcut(for: "no.such.action").isEmpty)
    }

    /// The registry has no conflict policy. This pins the current behaviour —
    /// both resolve, the collision is not detected — so that adding detection
    /// later is a deliberate change with a failing test to update, not a
    /// silent one.
    @Test func twoActionsBoundToTheSameShortcutBothResolve() {
        let registry = KeybindingRegistry(settings: KeybindingSettings(customBindings: [
            "find": "cmd+k",
            "foldAll": "cmd+k",
        ]))
        #expect(registry.shortcut(for: "find") == "cmd+k")
        #expect(registry.shortcut(for: "foldAll") == "cmd+k")
    }

    /// A hand-written binding that is not in shortcut syntax at all does not
    /// trap; it becomes a multi-character key equivalent, which AppKit will
    /// simply never match. Pinned so the failure mode stays visible.
    @Test func malformedShortcutBecomesAMultiCharacterKeyWithNoModifiers() {
        let registry = KeybindingRegistry(
            settings: KeybindingSettings(customBindings: ["find": "not a shortcut"]),
        )
        let equivalent = registry.keyEquivalent(for: "find")
        #expect(equivalent.key == "not a shortcut")
        #expect(equivalent.modifiers.isEmpty)
    }

    /// Trailing separators leave an empty final component, and the last
    /// non-modifier component wins — so this parses to no key at all rather
    /// than to "!!!".
    @Test func garbageShortcutParsesToAnEmptyKeyAndNoModifiers() {
        let parsed = KeybindingRegistry.parseShortcut("!!!+++")
        #expect(parsed.key.isEmpty)
        #expect(parsed.modifiers.isEmpty)
    }

    @Test func emptyShortcutStringParsesToNothing() {
        let parsed = KeybindingRegistry.parseShortcut("")
        #expect(parsed.key.isEmpty)
        #expect(parsed.modifiers.isEmpty)
    }

    /// Shift uppercases a single-character key because that is how AppKit
    /// menus express shifted equivalents, but it must leave a named special
    /// key alone — uppercasing an arrow-key scalar would stop it matching.
    @Test func shiftLeavesNamedSpecialKeysAlone() throws {
        let arrow = KeybindingRegistry.parseShortcut("cmd+shift+left")
        #expect(try arrow.key == String(#require(UnicodeScalar(NSLeftArrowFunctionKey))))
        #expect(arrow.modifiers.contains(.shift))
        #expect(arrow.modifiers.contains(.command))
    }

    @Test func specialKeyNamesResolveToTheirControlCharacters() {
        #expect(KeybindingRegistry.parseShortcut("cmd+tab").key == "\t")
        #expect(KeybindingRegistry.parseShortcut("cmd+escape").key == "\u{1b}")
        #expect(KeybindingRegistry.parseShortcut("cmd+space").key == " ")
    }

    @Test func modifierAliasesAreAccepted() {
        let alt = KeybindingRegistry.parseShortcut("alt+control+command+j")
        #expect(alt.modifiers.contains(.option))
        #expect(alt.modifiers.contains(.control))
        #expect(alt.modifiers.contains(.command))
        #expect(alt.key == "j")
    }
}
