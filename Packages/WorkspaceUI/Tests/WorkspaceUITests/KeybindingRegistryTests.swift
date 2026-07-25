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
}
