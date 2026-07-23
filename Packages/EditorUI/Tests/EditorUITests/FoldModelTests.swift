import DocumentCore
import SyntaxKit
import Testing
@testable import EditorUI

/// Deterministic RNG so a property-test failure is reproducible from its
/// printed seed (SplitMix64 — same construction as
/// `TextKit2EngineTests.SplitMix64` / `DocumentCoreTests.SeededRandom`).
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

struct FoldModelTests {
    /// "line0\nline1\n...\nline9\n" — every line is 6 bytes ("lineN\n").
    private var buffer: TextBuffer {
        TextBuffer((0 ..< 10).map { "line\($0)\n" }.joined())
    }

    private func region(_ startLine: Int, _ endLine: Int, depth: Int = 1) -> FoldRange {
        FoldRange(
            range: ByteOffset(startLine * 6) ..< ByteOffset(endLine * 6 + 5),
            startLine: startLine, endLine: endLine, depth: depth,
        )
    }

    @Test func foldHidesBodyLinesNotFirstLine() throws {
        var model = FoldModel()
        model.updateFoldable([region(1, 4)])
        try model.fold(#require(model.foldableRegion(atLine: 1)))
        #expect(model.hiddenLineSpans(in: buffer) == [2 ..< 5])
    }

    @Test func editAboveFoldShiftsAnchor() throws {
        var model = FoldModel()
        model.updateFoldable([region(2, 5)])
        try model.fold(#require(model.foldableRegion(atLine: 2)))
        // Insert "XY" at very start of buffer (2 bytes).
        let tx = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(0), replacement: "XY")],
            selectionBefore: SelectionSet(caretAt: ByteOffset(0)),
            selectionAfter: SelectionSet(caretAt: ByteOffset(2)),
            coalescingKey: nil,
            origin: .user,
        )
        model.apply(tx)
        // region(2, 5) is bytes 12 ..< 35; +2 inserted bytes before it.
        #expect(model.folded == [ByteOffset(14) ..< ByteOffset(37)])
    }

    @Test func editInsideFoldedRegionUnfoldsIt() throws {
        var model = FoldModel()
        model.updateFoldable([region(2, 5)])
        try model.fold(#require(model.foldableRegion(atLine: 2)))
        let tx = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(20) ..< ByteOffset(21), replacement: "Z")],
            selectionBefore: SelectionSet(caretAt: ByteOffset(20)),
            selectionAfter: SelectionSet(caretAt: ByteOffset(21)),
            coalescingKey: nil,
            origin: .user,
        )
        model.apply(tx)
        #expect(model.folded.isEmpty)
    }

    @Test func reconcileKeepsSurvivingAnchorsDropsVanished() throws {
        var model = FoldModel()
        model.updateFoldable([region(1, 4), region(6, 8)])
        try model.fold(#require(model.foldableRegion(atLine: 1)))
        try model.fold(#require(model.foldableRegion(atLine: 6)))
        // New parse: region at line 1 survives (same start), line-6 region gone.
        model.updateFoldable([region(1, 5)])
        #expect(model.folded.count == 1)
        #expect(model.hiddenLineSpans(in: buffer) == [2 ..< 6]) // adopted new extent
    }

    @Test func foldLevelFoldsExactDepthUnfoldsShallower() {
        var model = FoldModel()
        let outer = region(0, 9, depth: 1)
        let inner = region(2, 4, depth: 2)
        model.updateFoldable([outer, inner])
        model.fold(outer)
        model.foldLevel(2)
        #expect(model.folded == [inner.range]) // outer unfolded, inner folded
    }

    @Test func nestedFoldsMergeHiddenSpans() {
        var model = FoldModel()
        let outer = region(1, 8, depth: 1)
        let inner = region(3, 5, depth: 2)
        model.updateFoldable([outer, inner])
        model.foldAll()
        #expect(model.hiddenLineSpans(in: buffer) == [2 ..< 9])
    }

    @Test func unfoldEnclosingOpensWholeChain() {
        var model = FoldModel()
        let outer = region(1, 8, depth: 1)
        let inner = region(3, 5, depth: 2)
        model.updateFoldable([outer, inner])
        model.foldAll()
        model.unfoldEnclosing(ByteOffset(25)) // inside inner (line 4)
        #expect(model.folded.isEmpty)
    }

    @Test func isInsideHiddenTextExcludesFirstLine() throws {
        var model = FoldModel()
        model.updateFoldable([region(1, 4)])
        try model.fold(#require(model.foldableRegion(atLine: 1)))
        #expect(!model.isInsideHiddenText(ByteOffset(8), in: buffer)) // line 1 (visible first line)
        #expect(model.isInsideHiddenText(ByteOffset(14), in: buffer)) // line 2 (hidden)
        #expect(!model.isInsideHiddenText(ByteOffset(31), in: buffer)) // line 5 (after region)
    }

    @Test func gutterMarks() throws {
        var model = FoldModel()
        model.updateFoldable([region(1, 4), region(6, 8)])
        try model.fold(#require(model.foldableRegion(atLine: 6)))
        #expect(model.gutterMark(atLine: 0, in: buffer) == .none)
        #expect(model.gutterMark(atLine: 1, in: buffer) == .foldable)
        #expect(model.gutterMark(atLine: 6, in: buffer) == .folded)
    }

    /// Random edit scripts: FoldModel's incremental anchor adjustment must
    /// agree with recomputing from scratch. Reference semantics: a folded
    /// range survives a random edit iff the edit doesn't overlap it (a pure
    /// insertion exactly at either boundary never counts as overlap); its
    /// offsets shift by the total delta of edits strictly before it. Seed is
    /// randomized per run and printed on failure so a repro is reproducible.
    @Test func anchorAdjustmentMatchesReferenceUnderRandomEdits() {
        let seed = UInt64.random(in: .min ... .max)
        var rng = SplitMix64(seed: seed)
        for iteration in 0 ..< 200 {
            let text = (0 ..< 30).map { "line\($0)\n" }.joined()
            var buffer = TextBuffer(text)
            var model = FoldModel()
            let regionRange = ByteOffset(30) ..< ByteOffset(90)
            model.updateFoldable([
                FoldRange(
                    range: regionRange,
                    startLine: buffer.linePosition(of: regionRange.lowerBound).line,
                    endLine: buffer.linePosition(of: regionRange.upperBound).line,
                    depth: 1,
                ),
            ])
            model.fold(model.foldable[0])
            var expected: Range<ByteOffset>? = regionRange

            for step in 0 ..< 10 {
                let utf8Count = buffer.utf8Count
                let start = Int.random(in: 0 ... max(0, utf8Count - 2), using: &rng)
                let end = Int.random(in: start ... min(utf8Count, start + 4), using: &rng)
                let editRange = ByteOffset(start) ..< ByteOffset(end)
                let replacement = ["", "x", "xy\n"].randomElement(using: &rng)!
                let tx = EditTransaction(
                    baseVersion: buffer.version,
                    edits: [Edit(range: editRange, replacement: replacement)],
                    selectionBefore: SelectionSet(caretAt: editRange.lowerBound),
                    selectionAfter: SelectionSet(caretAt: editRange.lowerBound),
                    coalescingKey: nil,
                    origin: .user,
                )
                // Reference model.
                if let current = expected {
                    if editRange.lowerBound < current.upperBound, editRange.upperBound > current.lowerBound {
                        expected = nil // overlap → unfold
                    } else if editRange.upperBound <= current.lowerBound {
                        let delta = replacement.utf8.count - (end - start)
                        expected = ByteOffset(current.lowerBound.value + delta)
                            ..< ByteOffset(current.upperBound.value + delta)
                    } // edits entirely after: no shift
                }
                model.apply(tx)
                buffer.apply(tx)
                #expect(
                    model.folded == (expected.map { [$0] } ?? []),
                    "seed 0x\(String(seed, radix: 16)), iteration \(iteration), step \(step)",
                )
            }
        }
    }
}
