import Foundation
import SettingsKit
import Testing
@testable import WorkspaceUI

@MainActor
@Suite("PreferencesViewModelTests")
struct PreferencesViewModelTests {
    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspaceui-prefs-tests-\(UUID().uuidString)")
        return SettingsStore(directoryURL: dir)
    }

    @Test func initialValuesComeFromStore() {
        let store = makeStore()
        store.update { $0.editor.fontFamily = "Menlo"; $0.editor.fontSize = 16 }
        let viewModel = PreferencesViewModel(store: store)
        #expect(viewModel.fontFamily == "Menlo")
        #expect(viewModel.fontSize == 16)
    }

    @Test func changingFontSizeWritesThroughToStore() {
        let store = makeStore()
        let viewModel = PreferencesViewModel(store: store)
        viewModel.fontSize = 21
        #expect(store.current.editor.fontSize == 21)
    }

    @Test func changingTabWidthWritesThroughToStore() {
        let store = makeStore()
        let viewModel = PreferencesViewModel(store: store)
        viewModel.tabWidth = 8
        #expect(store.current.editor.tabWidth == 8)
    }

    @Test func externalStoreUpdateReflectsIntoViewModel() {
        let store = makeStore()
        let viewModel = PreferencesViewModel(store: store)
        store.update { $0.editor.fontSize = 24; $0.editor.tabWidth = 6 }
        #expect(viewModel.fontSize == 24)
        #expect(viewModel.tabWidth == 6)
    }

    /// Regression test: found via the final whole-branch review as the
    /// mirror image of a bug the manual feel-check found. Without a
    /// re-entrancy guard, `syncFromStore` reassigning a differing field
    /// (the correct behavior for reflecting an external change) also
    /// fires that field's `didSet`, which would call `store.update`
    /// again — silently re-persisting/reformatting a file the change
    /// didn't originate from in this view model. A single external
    /// `store.update` call must produce exactly one `onChange`
    /// notification, not a second echoed one.
    @Test func externalStoreUpdateDoesNotWriteBackToStore() {
        let store = makeStore()
        let viewModel = PreferencesViewModel(store: store)
        var notificationCount = 0
        store.onChange { _ in notificationCount += 1 }

        store.update { $0.editor.fontSize = 24 }

        #expect(viewModel.fontSize == 24)
        #expect(notificationCount == 1)
    }

    @Test func bannerReflectsLastLoadError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspaceui-prefs-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = SettingsStore(directoryURL: dir)

        let viewModel = PreferencesViewModel(store: store)
        #expect(viewModel.bannerMessage != nil)
    }

    @Test func bannerIsNilWhenNoError() {
        let store = makeStore()
        let viewModel = PreferencesViewModel(store: store)
        #expect(viewModel.bannerMessage == nil)
    }
}
