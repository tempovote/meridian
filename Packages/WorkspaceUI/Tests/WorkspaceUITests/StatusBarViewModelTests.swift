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
        .appendingPathComponent("editorui-settings-tests-\(UUID().uuidString)")
}

@MainActor
@Suite("StatusBarViewModelTests")
struct StatusBarViewModelTests {
    @Test func statusBarStateDerivedFromViewModel() {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        let vm = EditorViewModel(
            documentModel: DocumentModel(buffer: TextBuffer("First Line\nSecond Line")), engine: engine,
        )
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: vm.buffer)

        #expect(vm.currentCaretLineColumn.line == 1)
        #expect(vm.currentCaretLineColumn.column == 1)
        #expect(vm.selectionCharacterCount == 0)
        #expect(vm.lineCount == 2)

        let statusBar = StatusBarView(viewModel: vm, encodingName: "UTF-8", lineEndingName: "LF")
        #expect(statusBar.encodingName == "UTF-8")
        #expect(statusBar.lineEndingName == "LF")
    }
}
