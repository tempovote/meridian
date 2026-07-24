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

    /// A function whose body contains an `if` statement — two NESTED
    /// foldable regions (the `func` declaration, and the `if` inside it) —
    /// for the caret-reposition-under-nested-folds regression test.
    private func makeNestedSwiftEngine() async -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        engine.languageID = "swift"
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer("func outer() {\n    if true {\n        let x = 1\n    }\n}\n"))
        await engine.waitForParseForTesting()
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

    /// F1 regression: `NSDocument` revert reuses the same engine instance
    /// via `load(buffer:)` again — stale fold state from the OLD content
    /// must not survive into the newly loaded buffer (it would hide
    /// arbitrary lines of unrelated content until, if ever, a fresh parse
    /// lands).
    @Test func loadResetsStaleFoldState() async throws {
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        #expect(!engine.foldModelForTesting.folded.isEmpty)
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)

        engine.load(buffer: TextBuffer("line0\nline1\nline2\nline3\n"))

        #expect(engine.foldModelForTesting.folded.isEmpty)
        #expect(engine.foldModelForTesting.foldable.isEmpty)
        #expect(engine.hiddenUTF16SpansForTesting.isEmpty)

        // No zero-height (folded) fragments should remain from the old
        // document's collapsed lines.
        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        var sawZeroHeight = false
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            if fragment.layoutFragmentFrame.height == 0 {
                sawZeroHeight = true
            }
            return true
        }
        #expect(!sawZeroHeight)
    }

    /// F2 regression: the post-parse path (`highlightCurrentBuffer`'s
    /// completion) must not run the expensive TextKit 2 relayout/purge
    /// (`relayoutForFoldChange`, gated by `refreshFoldLayoutIfChanged`) on
    /// every reparse — only when hidden spans actually change. Also proves
    /// the purge path STILL fires on a real fold toggle (the opposite
    /// regression this fix must avoid introducing).
    @Test func postParseRefreshSkipsRelayoutWhenFoldStateUnchanged() async {
        let engine = await makeSwiftEngine()
        #expect(engine.foldRelayoutInvocationCountForTesting == 0) // initial parse: no folds yet, no relayout needed.

        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)
        #expect(engine.foldRelayoutInvocationCountForTesting == 1) // real fold toggle: purge DOES fire.

        let baseline = engine.foldRelayoutInvocationCountForTesting

        // Type elsewhere — past the folded region, so neither the folded
        // anchor nor any foldable region's bytes are affected — and let
        // the resulting reparse land.
        let endOfDocument = engine.snapshotForTesting.utf16Count
        engine.simulateUserTypingForTesting(replacing: NSRange(location: endOfDocument, length: 0), with: "z")
        await engine.waitForParseForTesting()

        #expect(engine.foldRelayoutInvocationCountForTesting == baseline) // unchanged: relayout was skipped.
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty) // fold itself is still intact.
    }

    /// F3 regression: folding with the caret mid-BODY (not on the region's
    /// first line, which is unaffected by folding) must not strand the
    /// caret inside the newly hidden text — else the very next selection
    /// change trips `unfoldIfSelectionEnteredHiddenText` and silently
    /// reverts the fold the user just requested.
    @Test func foldAtCaretMidBodyKeepsCaretVisible() async throws {
        let engine = await makeSwiftEngine()
        // "func f() {\n    let a = 1\n    let b = 2\n}\nlet tail = 3\n" — byte
        // 15 lands inside "    let a = 1" (line 1, the fold's hidden body).
        let midBodyOffset = ByteOffset(15)
        engine.setSelection(SelectionSet(caretAt: midBodyOffset), in: engine.snapshotForTesting)
        engine.foldAtCaret()

        #expect(engine.foldModelForTesting.folded.count == 1) // fold still applied...
        let caretAfter = engine.selection(in: engine.snapshotForTesting).ranges.first?.lowerBound
        #expect(caretAfter != nil)
        // ...and the caret is NOT left inside the hidden text.
        #expect(try !engine.foldModelForTesting.isInsideHiddenText(#require(caretAfter), in: engine.snapshotForTesting))

        // A subsequent selection-change to that same (now-visible) location
        // must not trip the hidden-text guard and unfold it.
        try engine.setSelection(SelectionSet(caretAt: #require(caretAfter)), in: engine.snapshotForTesting)
        #expect(engine.foldModelForTesting.folded.count == 1)
    }

    /// F3 nested-fold regression: with the caret in a doubly-nested
    /// region's body, `foldAll()` folds BOTH the outer `func` and the
    /// inner `if` at once. Repositioning the caret to the INNER region's
    /// first line isn't enough — that line is itself hidden inside the
    /// OUTER fold — so it must walk outward until it lands somewhere
    /// genuinely visible, or `foldAll()` instantly undoes itself around
    /// the caret (via the synchronous `unfoldIfSelectionEnteredHiddenText`
    /// -> `unfoldEnclosing` guard unfolding the whole chain).
    @Test func foldAllWithCaretInNestedBodyKeepsBothFoldsIntact() async throws {
        let engine = await makeNestedSwiftEngine()
        // "func outer() {\n    if true {\n        let x = 1\n    }\n}\n" — byte
        // 35 lands inside "        let x = 1" (the innermost, doubly-hidden body).
        let innerBodyOffset = ByteOffset(35)
        engine.setSelection(SelectionSet(caretAt: innerBodyOffset), in: engine.snapshotForTesting)
        engine.foldAll()

        #expect(engine.foldModelForTesting.folded.count == 2) // BOTH folds still intact...
        let caretAfter = engine.selection(in: engine.snapshotForTesting).ranges.first?.lowerBound
        #expect(caretAfter != nil)
        // ...and the caret landed somewhere genuinely visible, not merely
        // moved to another (still-hidden) nested first line.
        #expect(try !engine.foldModelForTesting.isInsideHiddenText(#require(caretAfter), in: engine.snapshotForTesting))
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)

        // A subsequent selection-change/guard invocation at that same
        // location must not unfold anything either.
        try engine.setSelection(SelectionSet(caretAt: #require(caretAfter)), in: engine.snapshotForTesting)
        #expect(engine.foldModelForTesting.folded.count == 2)
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)
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

    @Test func coalescedDeferredFoldRelayoutFiresSingleRelayoutForBurstEdits() async {
        let engine = await makeSwiftEngine()
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: engine.snapshotForTesting)
        engine.foldAtCaret()
        #expect(!engine.foldModelForTesting.folded.isEmpty)

        // Rapid user typing edits inside the fold body schedule deferred fold relayout passes.
        let utf16 = engine.snapshotForTesting.utf16Offset(of: ByteOffset(15)).value
        engine.simulateUserTypingForTesting(replacing: NSRange(location: utf16, length: 0), with: "a")
        engine.simulateUserTypingForTesting(replacing: NSRange(location: utf16 + 1, length: 0), with: "b")

        await engine.waitForDeferredFoldRelayoutForTesting()
        // Editing into the folded region unfolds it, and the deferred task completes safely.
        #expect(engine.foldModelForTesting.folded.isEmpty)
    }

    @Test func foldAtCaretWorksWithNonEmptySelection() async {
        let engine = await makeSwiftEngine()
        // Select range 0..<5 ("func ")
        engine.setSelection(SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(5)]), in: engine.snapshotForTesting)
        #expect(engine.canFoldAtCaret)
        engine.foldAtCaret()
        #expect(engine.foldModelForTesting.folded.count == 1)
        #expect(engine.canUnfoldAtCaret)
        engine.unfoldAtCaret()
        #expect(engine.foldModelForTesting.folded.isEmpty)
    }
}
