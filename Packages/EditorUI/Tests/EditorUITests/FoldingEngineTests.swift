import AppKit
import DocumentCore
import SettingsKit
import Testing
import ThemeKit
@testable import EditorUI

/// A fresh, unique temp directory per call — real `SettingsStore`
/// instances only (this repo doesn't mock; ARCHITECTURE §15). Mirrors the
/// helper in `FoldingRenderTests.swift`/`TextKit2EngineTests.swift`.
private func testSettingsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("editorui-settings-tests-\(UUID().uuidString)")
}

/// End-to-end fold data flow: parse → `FoldModel` → hidden line spans, the
/// fold operations that mutate it, and the auto-unfold rules (typing into
/// a fold, navigating into hidden text, a mirrored sibling-pane edit).
@MainActor
struct FoldingEngineTests {
    private func makeSwiftEngine() async -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        engine.languageID = "swift"
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer("func f() {\n    let a = 1\n    let b = 2\n}\nlet tail = 3\n"))
        await engine.waitForParseForTesting() // new DEBUG hook — see Step 3
        return engine
    }

    @Test func parsePopulatesFoldModel() async {
        let engine = await makeSwiftEngine()
        #expect(!engine.foldModelForTesting.foldable.isEmpty)
    }

    @Test func foldAtCaretHidesBodyAndGutterSkips() async {
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        #expect(engine.foldModelForTesting.folded.count == 1)
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)
    }

    @Test func typingInsideFoldedRegionUnfolds() async {
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        // Simulate an edit landing inside the folded body (line 1).
        let utf16 = engine.snapshotForTesting.utf16Offset(of: ByteOffset(15)).value
        engine.simulateUserTypingForTesting(replacing: NSRange(location: utf16, length: 0), with: "x")
        #expect(engine.foldModelForTesting.folded.isEmpty)
        #expect(engine.hiddenUTF16SpansForTesting.isEmpty)
    }

    @Test func settingSelectionIntoHiddenTextUnfolds() async {
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        // Goto/find path: place the caret on a hidden line.
        engine.setSelection(SelectionSet(caretAt: ByteOffset(15)), in: engine.snapshotForTesting)
        #expect(engine.foldModelForTesting.folded.isEmpty)
    }

    @Test func foldAllThenUnfoldAll() async {
        let engine = await makeSwiftEngine()
        engine.foldAll()
        #expect(!engine.foldModelForTesting.folded.isEmpty)
        engine.unfoldAll()
        #expect(engine.foldModelForTesting.folded.isEmpty)
        #expect(engine.hiddenUTF16SpansForTesting.isEmpty)
    }

    @Test func mirroredSiblingEditIntoFoldUnfolds() async {
        // Split-pane rule: apply(_:base:restoreSelection:false) touching a
        // folded region unfolds it in THIS pane too.
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        let base = engine.snapshotForTesting
        let tx = EditTransaction(
            baseVersion: base.version,
            edits: [Edit(range: ByteOffset(15) ..< ByteOffset(15), replacement: "x")],
            selectionBefore: SelectionSet(caretAt: ByteOffset(15)),
            selectionAfter: SelectionSet(caretAt: ByteOffset(16)),
            coalescingKey: nil,
            origin: .user,
        )
        engine.apply(tx, base: base, restoreSelection: false)
        #expect(engine.foldModelForTesting.folded.isEmpty)
    }
}
