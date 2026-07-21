import AppKit
import DocumentCore
import Testing
import ThemeKit
@testable import EditorUI

@MainActor
@Suite("SoftWrapAndChromeTests")
struct SoftWrapAndChromeTests {
    @Test func viewModelTogglesAndDerivedProperties() {
        let engine = MockLayoutEngine()
        let vm = EditorViewModel(buffer: TextBuffer("Hello\nWorld\nFoo"), engine: engine)

        #expect(vm.isGutterVisible)
        #expect(vm.isSoftWrapEnabled)
        #expect(vm.isCurrentLineHighlightEnabled)
        #expect(vm.isStatusBarVisible)
        #expect(vm.lineCount == 3)

        // Caret at offset 0 -> Line 1, Col 1
        #expect(vm.currentCaretLineColumn.line == 1)
        #expect(vm.currentCaretLineColumn.column == 1)
        #expect(vm.selectionCharacterCount == 0)

        // Toggle state
        vm.isGutterVisible = false
        #expect(!vm.isGutterVisible)

        vm.isSoftWrapEnabled = false
        #expect(!vm.isSoftWrapEnabled)
    }

    @Test func textKit2EngineSoftWrapAndGutterToggles() {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(themeEngine: themeEngine)
        let vm = EditorViewModel(buffer: TextBuffer("Line 1\nLine 2"), engine: engine)

        engine.setSoftWrap(true)
        engine.setSoftWrap(false)

        engine.setGutterVisible(true)
        engine.setGutterVisible(false)

        #expect(vm.lineCount == 2)
    }
}
