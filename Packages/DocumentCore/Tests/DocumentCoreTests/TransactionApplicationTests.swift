import Testing
@testable import DocumentCore

@Test func applySingleEditMatchesReplaceSubrange() {
    var viaTxn = TextBuffer("hello world")
    var viaReplace = viaTxn
    let txn = EditTransaction(
        baseVersion: viaTxn.version,
        edits: [Edit(range: ByteOffset(6) ..< ByteOffset(11), replacement: "Meridian")],
    )
    viaTxn.apply(txn)
    viaReplace.replaceSubrange(ByteOffset(6) ..< ByteOffset(11), with: "Meridian")
    #expect(viaTxn.string == viaReplace.string)
    #expect(viaTxn.string == "hello Meridian")
}

@Test func applyBumpsVersionExactlyOnce() {
    var buffer = TextBuffer("abcd")
    let before = buffer.version
    let txn = EditTransaction(
        baseVersion: before,
        edits: [
            Edit(range: ByteOffset(0) ..< ByteOffset(1), replacement: "X"),
            Edit(range: ByteOffset(2) ..< ByteOffset(3), replacement: "Y"),
        ],
    )
    buffer.apply(txn)
    #expect(buffer.version.value == before.value + 1)
    #expect(buffer.string == "XbYd")
}

@Test func multiEditAppliesInBaseCoordinates() {
    // All ranges refer to the ORIGINAL buffer; deltas must not shift later edits.
    var buffer = TextBuffer("0123456789")
    let txn = EditTransaction(
        baseVersion: buffer.version,
        edits: [
            Edit(range: ByteOffset(1) ..< ByteOffset(3), replacement: "aaaa"), // grows
            Edit(range: ByteOffset(5) ..< ByteOffset(8), replacement: ""), // shrinks
            Edit(range: ByteOffset(9) ..< ByteOffset(9), replacement: "z"), // insert
        ],
    )
    buffer.apply(txn)
    #expect(buffer.string == "0aaaa348z9")
}

@Test func invertedUndoesSingleEdit() {
    let base = TextBuffer("hello world")
    var buffer = base
    let txn = EditTransaction(
        baseVersion: base.version,
        edits: [Edit(range: ByteOffset(0) ..< ByteOffset(5), replacement: "goodbye")],
        selectionBefore: SelectionSet(caretAt: ByteOffset(5)),
        selectionAfter: SelectionSet(caretAt: ByteOffset(7)),
    )
    let inverse = txn.inverted(base: base)
    buffer.apply(txn)
    #expect(buffer.string == "goodbye world")
    #expect(inverse.baseVersion == buffer.version)
    #expect(inverse.selectionBefore == txn.selectionAfter)
    #expect(inverse.selectionAfter == txn.selectionBefore)
    buffer.apply(inverse)
    #expect(buffer.string == "hello world")
}

@Test func invertedUndoesMultiEdit() {
    let base = TextBuffer("0123456789")
    var buffer = base
    let txn = EditTransaction(
        baseVersion: base.version,
        edits: [
            Edit(range: ByteOffset(1) ..< ByteOffset(3), replacement: "aaaa"),
            Edit(range: ByteOffset(5) ..< ByteOffset(8), replacement: ""),
            Edit(range: ByteOffset(9) ..< ByteOffset(9), replacement: "z"),
        ],
    )
    let inverse = txn.inverted(base: base)
    buffer.apply(txn)
    buffer.apply(inverse)
    #expect(buffer.string == "0123456789")
}

@Test func inverseReplacementsShareBaseContent() {
    let base = TextBuffer(String(repeating: "x", count: 10000))
    let txn = EditTransaction(
        baseVersion: base.version,
        edits: [Edit(range: ByteOffset(0) ..< ByteOffset(10000), replacement: "")],
    )
    let inverse = txn.inverted(base: base)
    #expect(inverse.edits[0].replacement.utf8Count == 10000)
    #expect(inverse.edits[0].range == ByteOffset(0) ..< ByteOffset(0))
}

/// Property test: random multi-edit transactions on random buffers;
/// apply ∘ apply(inverse) must be the identity on content.
@Test func randomTransactionsInvertCleanly() {
    var rng = SeededRandom(seed: 0x4D31_5035)
    for round in 0 ..< 200 {
        var text = ""
        for _ in 0 ..< 20 {
            text += fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
        }
        let base = TextBuffer(text)
        let bytes = Array(text.utf8)
        // Build 1–4 sorted, non-overlapping edits on scalar boundaries.
        var cuts: Set<Int> = []
        while cuts.count < 8 {
            cuts.insert(randomScalarBoundary(in: bytes, using: &rng))
        }
        let sorted = cuts.sorted()
        var edits: [Edit] = []
        var index = 0
        while index + 1 < sorted.count, edits.count < 4 {
            let lower = sorted[index]
            let upper = sorted[index + 1]
            let snippet = fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
            edits.append(Edit(range: ByteOffset(lower) ..< ByteOffset(upper), replacement: snippet))
            index += 2
        }
        let txn = EditTransaction(baseVersion: base.version, edits: edits)
        let inverse = txn.inverted(base: base)
        var buffer = base
        buffer.apply(txn)
        buffer.apply(inverse)
        #expect(buffer.string == text, "round \(round) diverged")
    }
}
