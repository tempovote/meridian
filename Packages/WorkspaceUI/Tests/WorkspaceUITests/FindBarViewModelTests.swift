import DocumentCore
import EditorUI
import Foundation
import SettingsKit
import Testing
import ThemeKit
import WorkspaceUI

/// A fresh, unique temp directory per call — real `SettingsStore`
/// instances only (this repo doesn't mock; ARCHITECTURE §15).
private func testSettingsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("findbar-viewmodel-tests-\(UUID().uuidString)")
}

@MainActor
private func makeViewModel(text: String, startExpanded: Bool = false) -> FindBarViewModel {
    let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
    let engine = TextKit2Engine(
        themeEngine: themeEngine,
        settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
    )
    let editorViewModel = EditorViewModel(documentModel: DocumentModel(buffer: TextBuffer(text)), engine: engine)
    return FindBarViewModel(editorViewModel: editorViewModel, startExpanded: startExpanded)
}

@MainActor
@Suite("FindBarViewModelTests")
struct FindBarViewModelTests {
    @Test func performSearchPopulatesMatches() {
        let viewModel = makeViewModel(text: "foo bar foo baz foo")
        viewModel.query = "foo"
        viewModel.performSearch()
        #expect(viewModel.matches.count == 3)
        #expect(viewModel.currentMatchIndex == 0)
    }

    @Test func performSearchWithEmptyQueryClearsMatches() {
        let viewModel = makeViewModel(text: "foo bar foo")
        viewModel.query = "foo"
        viewModel.performSearch()
        #expect(!viewModel.matches.isEmpty)

        viewModel.query = ""
        viewModel.performSearch()
        #expect(viewModel.matches.isEmpty)
        #expect(viewModel.currentMatchIndex == 0)
    }

    @Test func findNextWrapsAroundToFirstMatch() {
        let viewModel = makeViewModel(text: "foo bar foo baz foo")
        viewModel.query = "foo"
        viewModel.performSearch()

        viewModel.findNext()
        #expect(viewModel.currentMatchIndex == 1)
        viewModel.findNext()
        #expect(viewModel.currentMatchIndex == 2)
        viewModel.findNext()
        #expect(viewModel.currentMatchIndex == 0)
    }

    @Test func findPreviousWrapsAroundToLastMatch() {
        let viewModel = makeViewModel(text: "foo bar foo baz foo")
        viewModel.query = "foo"
        viewModel.performSearch()

        viewModel.findPrevious()
        #expect(viewModel.currentMatchIndex == 2)
    }

    @Test func findNextWithNoMatchesIsANoOp() {
        let viewModel = makeViewModel(text: "foo bar")
        viewModel.query = "zzz"
        viewModel.performSearch()
        viewModel.findNext()
        #expect(viewModel.currentMatchIndex == 0)
    }

    @Test func matchCountTextReflectsSearchState() {
        let viewModel = makeViewModel(text: "foo bar foo")
        #expect(viewModel.matchCountText == "")

        viewModel.query = "zzz"
        viewModel.performSearch()
        #expect(viewModel.matchCountText == "No results")

        viewModel.query = "foo"
        viewModel.performSearch()
        #expect(viewModel.matchCountText == "1 of 2")

        viewModel.findNext()
        #expect(viewModel.matchCountText == "2 of 2")
    }

    @Test func replaceCurrentReplacesOnlyTheSelectedMatch() {
        let viewModel = makeViewModel(text: "foo bar foo")
        viewModel.query = "foo"
        viewModel.performSearch()
        viewModel.replacement = "baz"

        viewModel.replaceCurrent()

        #expect(viewModel.matches.count == 1)
    }

    @Test func replaceAllReplacesEveryMatch() {
        let viewModel = makeViewModel(text: "foo bar foo baz foo")
        viewModel.query = "foo"
        viewModel.performSearch()
        viewModel.replacement = "qux"

        viewModel.replaceAll()

        #expect(viewModel.matches.isEmpty)
    }

    @Test func isBoundToDistinguishesEditorViewModels() {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engineA = TextKit2Engine(
            themeEngine: themeEngine, settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        let engineB = TextKit2Engine(
            themeEngine: themeEngine, settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        let editorA = EditorViewModel(documentModel: DocumentModel(buffer: TextBuffer("a")), engine: engineA)
        let editorB = EditorViewModel(documentModel: DocumentModel(buffer: TextBuffer("b")), engine: engineB)
        let viewModel = FindBarViewModel(editorViewModel: editorA)

        #expect(viewModel.isBound(to: editorA))
        #expect(!viewModel.isBound(to: editorB))
    }

    @Test func startExpandedSeedsIsReplaceExpanded() {
        let collapsed = makeViewModel(text: "foo", startExpanded: false)
        #expect(!collapsed.isReplaceExpanded)

        let expanded = makeViewModel(text: "foo", startExpanded: true)
        #expect(expanded.isReplaceExpanded)
    }
}
