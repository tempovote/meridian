import AppKit
import DocumentCore
import SettingsKit
import Testing
import ThemeKit
@testable import EditorUI

/// A fresh, unique temp directory per call — real `SettingsStore`
/// instances only (this repo doesn't mock; ARCHITECTURE §15).
private func testSettingsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("editorui-settings-tests-\(UUID().uuidString)")
}

/// Renders a real TextKit 2 engine offscreen and asserts hidden line spans
/// produce zero-height layout fragments (the fold primitive) while the
/// content storage keeps the full text.
@MainActor
struct FoldingRenderTests {
    private func makeEngine(_ text: String) -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        // Give the view a real size so TextKit 2 lays out (same trick as
        // existing TextKit2EngineTests / SoftWrapAndChromeTests).
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer(text))
        return engine
    }

    @Test func hiddenSpanCollapsesFragmentsToZeroHeight() throws {
        let engine = makeEngine("line0\nline1\nline2\nline3\nline4\n")
        engine.setHiddenLineSpans([1 ... 2].map { Range($0) })

        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)

        var heightsByLine: [Int: CGFloat] = [:]
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let offset = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            let line = engine.snapshotForTesting
                .linePosition(of: engine.snapshotForTesting.byteOffset(of: UTF16Offset(offset))).line
            heightsByLine[line] = fragment.layoutFragmentFrame.height
            return true
        }
        #expect(heightsByLine[0] ?? 0 > 0)
        #expect(heightsByLine[1] == 0)
        #expect(heightsByLine[2] == 0)
        #expect(heightsByLine[3] ?? 0 > 0)
        // Content storage still holds the full text — folding is display-only.
        #expect(engine.storageStringForTesting == "line0\nline1\nline2\nline3\nline4\n")
    }

    @Test func clearingSpansRestoresHeights() throws {
        let engine = makeEngine("a\nb\nc\n")
        engine.setHiddenLineSpans([1 ... 1].map { Range($0) })
        engine.setHiddenLineSpans([])
        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        var zeroHeightCount = 0
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            if fragment.layoutFragmentFrame.height == 0 {
                zeroHeightCount += 1
            }
            return true
        }
        #expect(zeroHeightCount == 0)
    }

    /// Maps each laid-out fragment's height to the (rope) line it starts
    /// at, the same technique `hiddenSpanCollapsesFragmentsToZeroHeight`
    /// uses — factored out so the regression tests below can reuse it.
    private func heightsByLine(_ engine: TextKit2Engine) throws -> [Int: CGFloat] {
        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        var heights: [Int: CGFloat] = [:]
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let offset = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            let line = engine.snapshotForTesting
                .linePosition(of: engine.snapshotForTesting.byteOffset(of: UTF16Offset(offset))).line
            heights[line] = fragment.layoutFragmentFrame.height
            return true
        }
        return heights
    }

    /// Regression for a crash: an empty span (`0..<0`) made `endLine`
    /// compute to `-1`, and `byteRange(ofLine: -1)` traps. Combined with a
    /// span entirely past `lineCount` (filtered by the existing
    /// `lowerBound` guard) and a span covering the buffer's true last line
    /// (no trailing newline, so its byte range extends to `utf8Count`) to
    /// exercise all three boundary shapes in one call.
    @Test func emptyAndOutOfRangeSpansDoNotCrashAndLastLineFolds() throws {
        let engine = makeEngine("a\nb\nc") // no trailing newline: lineCount == 3, "c" is the true last line.
        engine.setHiddenLineSpans([0 ..< 0, 10 ..< 20, 2 ..< 3])

        let heights = try heightsByLine(engine)
        #expect(heights[0] ?? 0 > 0) // "a" untouched by the empty span.
        #expect(heights[1] ?? 0 > 0) // "b" untouched by the out-of-range span.
        #expect(heights[2] == 0) // "c", the true last line, folded.
    }

    /// Regression: `byteRange(ofLine:)` excludes a line's trailing `\n`,
    /// so computing a span's end from the *hidden* last line's own byte
    /// range collapses to that line's start when the last hidden line is
    /// blank — leaving it visible. The fix derives the end from the
    /// *next* line's start instead.
    @Test func blankLastLineOfHiddenSpanFolds() throws {
        let engine = makeEngine("a\n\nc\n") // line0 "a", line1 "" (blank), line2 "c".
        engine.setHiddenLineSpans([0 ..< 2]) // hide "a" and the blank line.

        let heights = try heightsByLine(engine)
        #expect(heights[0] == 0) // "a" folded.
        #expect(heights[1] == 0) // the blank line — this is the regression.
        #expect(heights[2] ?? 0 > 0) // "c" stays visible.
    }

    /// Regression: `isHiddenParagraph`'s binary search assumes the stored
    /// spans are sorted *and disjoint*. A caller (a future `FoldModel`) may
    /// legitimately pass nested/overlapping spans — `setHiddenLineSpans`
    /// must merge them before storing, or the search can silently
    /// mis-answer a query that lies inside the *outer* span but past the
    /// last *nested* one.
    ///
    /// Concretely: sorted by start, `[0..<20, 2..<3, 10..<12]` is exactly
    /// the shape that broke the unmerged search — querying line 15 (inside
    /// the enclosing 0..<20 span, but the search only ever compares
    /// against the nested 2..<3 and 10..<12 entries once it steps past
    /// index 0) walked right past the enclosing entry and never revisited
    /// it, incorrectly reporting line 15 as visible.
    @Test func nestedAndOverlappingInputSpansAreMergedCorrectly() throws {
        let lineText = (0 ... 22).map { "l\($0)" }.joined(separator: "\n") + "\n"
        let engine = makeEngine(lineText)
        engine.setHiddenLineSpans([0 ..< 20, 2 ..< 3, 10 ..< 12])

        let heights = try heightsByLine(engine)
        #expect(heights[0] == 0) // start of the enclosing span.
        #expect(heights[3] == 0) // inside the enclosing span, at a nested span's edge.
        #expect(heights[15] == 0) // the binary-search blind spot — the actual regression.
        #expect(heights[19] == 0) // last line covered by the enclosing span.
        #expect(heights[20] ?? 0 > 0) // right after the merged span ends.
        #expect(heights[22] ?? 0 > 0) // untouched tail line.
    }
}
