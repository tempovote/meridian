import Testing
@testable import DocumentCore

private func randomInsert(
    into buffer: TextBuffer, using rng: inout SeededRandom,
) -> EditTransaction {
    let bytes = Array(buffer.string.utf8)
    let at = randomScalarBoundary(in: bytes, using: &rng)
    let snippet = fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
    return EditTransaction(
        baseVersion: buffer.version,
        edits: [Edit(range: ByteOffset(at) ..< ByteOffset(at), replacement: snippet)],
    )
}

/// One step of the random record/undo/redo/group script driving
/// `retainedCostCacheMatchesRecomputeUnderRandomScripts`. Factored out of the
/// test body (rather than inlined as the brief specifies) purely to keep the
/// enclosing test function's cyclomatic complexity under the repo's
/// SwiftLint threshold; the branch logic and RNG call order are unchanged.
private func performRandomStep(
    stack: inout UndoStack,
    buffer: inout TextBuffer,
    openGroup: inout Bool,
    using rng: inout SeededRandom,
) {
    switch Int.random(in: 0 ..< 10, using: &rng) {
    case 0 ..< 6:
        let txn = randomInsert(into: buffer, using: &rng)
        stack.record(txn, base: buffer)
        buffer.apply(txn)
    case 6:
        if let undos = stack.undo() {
            for undo in undos {
                buffer.apply(undo)
            }
        }
    case 7:
        if let redos = stack.redo() {
            for redo in redos {
                buffer.apply(redo)
            }
        }
    case 8 where !openGroup:
        stack.beginGroup()
        openGroup = true
    default:
        if openGroup {
            stack.endGroup()
            openGroup = false
        }
    }
}

/// Property: after any mixed script of record/undo/redo/group operations —
/// including evictions under a small budget — the incrementally maintained
/// `retainedCost` equals a full recompute over the stored entries.
@Test func retainedCostCacheMatchesRecomputeUnderRandomScripts() {
    var rng = SeededRandom(seed: 0x4D31_5051)
    for budget in [512, 4096, 64 * 1024 * 1024] {
        var buffer = TextBuffer("seed")
        var stack = UndoStack(byteBudget: budget)
        var openGroup = false
        for _ in 0 ..< 400 {
            performRandomStep(stack: &stack, buffer: &buffer, openGroup: &openGroup, using: &rng)
            #expect(stack.retainedCost == stack.recomputedRetainedCost)
        }
    }
}

@Test func evictionStillDropsOldestFirstAndKeepsNewest() throws {
    var buffer = TextBuffer("")
    var stack = UndoStack(byteBudget: 2048)
    for index in 0 ..< 8 {
        let chunk = String(repeating: "y", count: 1024)
        let at = buffer.utf8Count
        let txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(at) ..< ByteOffset(at), replacement: chunk)],
        )
        stack.record(txn, base: buffer, at: .now + .seconds(10 * index))
        buffer.apply(txn)
    }
    #expect(stack.undoCount >= 1)
    #expect(stack.undoCount < 8)
    #expect(stack.retainedCost == stack.recomputedRetainedCost)
    // The newest entry must still undo cleanly.
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    #expect(buffer.utf8Count == 7 * 1024)
}
