import DocumentCore
import EditorUI
import ThemeKit
import Testing
import WorkspaceUI

@MainActor
@Suite("StatusBarViewModelTests")
struct StatusBarViewModelTests {
    @Test func statusBarStateDerivedFromViewModel() {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(themeEngine: themeEngine)
        let vm = EditorViewModel(buffer: TextBuffer("First Line\nSecond Line"), engine: engine)
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
