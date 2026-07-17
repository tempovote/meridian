import Testing
@testable import DocumentCore

private struct UndoFuzzModel {
    var undoContents: [String] = []
    var redoContents: [String] = []
}

/// Whether an explicit group is currently open, and whether it has received
/// its first `record` yet. Bundled into one type (rather than two separate
/// `inout` parameters, as the brief's inline code uses) purely to keep the
/// step functions below at the repo's SwiftLint parameter-count limit; the
/// fields and their read/write sites are otherwise identical to the brief.
private struct GroupState {
    var isOpen = false
    var pushed = false
}

/// Content size above which `recordRandomFuzzEdit` switches to delete-biased
/// edits, mirroring `BufferFuzzEngine.sizeCap`'s role: unlike that engine,
/// this fuzz has no built-in delete bias, and `fuzzCorpus` includes a
/// 3000-byte snippet, so uncapped growth makes every op's `buffer.string`
/// materialization (and the underlying rope work) increasingly expensive —
/// this cap keeps wall time roughly linear in operation count instead of
/// superlinear. 64 KiB matches `BufferFuzzEngine`'s own choice of "small
/// enough to stay cheap, large enough to still exercise multi-leaf ropes".
private let undoFuzzSizeCap = 64 * 1024

/// Maximum span of a size-cap delete edit, in bytes.
private let undoFuzzMaxDeleteSpan = 512

/// Records a random edit transaction against `buffer`/`stack`: applies the
/// transaction to both, and — mirroring `UndoStack.record`'s own
/// group/coalescing rule — pushes the pre-apply content onto the model's
/// undo stack (inside an open group, only the group's first record pushes).
/// A fresh edit always invalidates redo. Factored out of `undoFuzz`'s body
/// (rather than inlined as the brief specifies) purely to keep the enclosing
/// test function's cyclomatic complexity under the repo's SwiftLint
/// threshold; the branch logic is otherwise unchanged from the brief.
///
/// Above `undoFuzzSizeCap`, the edit is forced delete-biased (a random
/// scalar-boundary range up to `undoFuzzMaxDeleteSpan` bytes, replaced with
/// empty content) instead of the normal insert/replace-with-corpus-snippet,
/// to keep the buffer's content size — and thus each op's `buffer.string`
/// materialization cost — bounded. This skips the corpus-index RNG draw
/// while over the cap (there's no snippet to pick), so the exact RNG draw
/// sequence differs from an uncapped run once the cap is first reached; the
/// `at`-boundary draw itself is always made first, uncapped or not, so
/// sub-cap runs (including the whole small-budget/8 KiB case, which evicts
/// long before content could reach 64 KiB) are byte-for-byte unaffected.
private func recordRandomFuzzEdit(
    stack: inout UndoStack,
    buffer: inout TextBuffer,
    model: inout UndoFuzzModel,
    group: inout GroupState,
    using rng: inout SeededRandom,
) {
    let bytes = Array(buffer.string.utf8)
    let at = randomScalarBoundary(in: bytes, using: &rng)
    let txn: EditTransaction
    if bytes.count > undoFuzzSizeCap {
        let upper = scalarBoundary(in: bytes, notAfter: min(at + undoFuzzMaxDeleteSpan, bytes.count))
        txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(at) ..< ByteOffset(max(at, upper)), replacement: "")],
        )
    } else {
        let upper = scalarBoundary(in: bytes, notAfter: min(at + 32, bytes.count))
        let snippet = fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
        txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(at) ..< ByteOffset(max(at, upper)), replacement: snippet)],
        )
    }
    let before = buffer.string
    stack.record(txn, base: buffer)
    buffer.apply(txn)
    if group.isOpen {
        if !group.pushed {
            model.undoContents.append(before)
            group.pushed = true
        }
    } else {
        model.undoContents.append(before)
    }
    model.redoContents.removeAll()
}

/// Closes any open group (undo mid-composite ends the composite), then
/// undoes the top entry if one exists and checks the restored content
/// against the model's undo stack. Extracted alongside
/// `recordRandomFuzzEdit` for the same complexity reason.
private func performRandomUndo(
    stack: inout UndoStack,
    buffer: inout TextBuffer,
    model: inout UndoFuzzModel,
    group: inout GroupState,
    context: String,
) {
    if group.isOpen {
        stack.endGroup()
        group.isOpen = false
    }
    if let undos = stack.undo() {
        let after = buffer.string
        for undo in undos {
            buffer.apply(undo)
        }
        let expected = model.undoContents.removeLast()
        model.redoContents.append(after)
        #expect(buffer.string == expected, "undo diverged (\(context))")
    } else {
        #expect(model.undoContents.isEmpty || stack.undoCount == 0, "undo unexpectedly empty (\(context))")
    }
}

/// Closes any open group, then redoes the top redo entry if one exists and
/// checks the reapplied content against the model's redo stack. Extracted
/// alongside `recordRandomFuzzEdit` for the same complexity reason.
private func performRandomRedo(
    stack: inout UndoStack,
    buffer: inout TextBuffer,
    model: inout UndoFuzzModel,
    group: inout GroupState,
    context: String,
) {
    if group.isOpen {
        stack.endGroup()
        group.isOpen = false
    }
    if let redos = stack.redo() {
        let before = buffer.string
        for redo in redos {
            buffer.apply(redo)
        }
        let expected = model.redoContents.removeLast()
        model.undoContents.append(before)
        #expect(buffer.string == expected, "redo diverged (\(context))")
    } else {
        #expect(model.redoContents.isEmpty, "redo unexpectedly empty (\(context))")
    }
}

/// #10 — random record/undo/redo/group scripts vs a content-stack reference
/// model, under both a huge budget (no eviction) and a small one (eviction
/// exercised); the retained-cost cache must match a recompute throughout.
@Test(arguments: [64 * 1024 * 1024, 8 * 1024])
func undoFuzz(budget: Int) {
    var rng = SeededRandom(seed: FuzzConfig.seed &+ UInt64(budget))
    let operations = max(FuzzConfig.operations / 4, 2000)
    var buffer = TextBuffer("undo-fuzz")
    var stack = UndoStack(byteBudget: budget)
    var model = UndoFuzzModel()
    var group = GroupState()

    for opIndex in 0 ..< operations {
        let context = "seed 0x\(String(FuzzConfig.seed, radix: 16)), budget \(budget), op \(opIndex)"
        switch Int.random(in: 0 ..< 100, using: &rng) {
        case 0 ..< 65:
            recordRandomFuzzEdit(stack: &stack, buffer: &buffer, model: &model, group: &group, using: &rng)
        case 65 ..< 80:
            performRandomUndo(stack: &stack, buffer: &buffer, model: &model, group: &group, context: context)
        case 80 ..< 90:
            performRandomRedo(stack: &stack, buffer: &buffer, model: &model, group: &group, context: context)
        case 90 ..< 95 where !group.isOpen:
            stack.beginGroup()
            group.isOpen = true
            group.pushed = false
        default:
            if group.isOpen {
                stack.endGroup()
                group.isOpen = false
            }
        }
        // `beginGroup()` appends an empty placeholder `Entry` to `entries`
        // immediately (before any `record`), so `stack.undoCount` counts it
        // the instant a group opens — one op before the model's first push
        // for that group. Subtract it back out so both sides count only
        // entries the model actually knows about; it can never itself be
        // evicted while pending (it's always the newest entry, and
        // `evict()` only drops the oldest while more than one remains).
        let pendingGroupEntry = group.isOpen && !group.pushed
        let realUndoCount = stack.undoCount - (pendingGroupEntry ? 1 : 0)
        #expect(stack.retainedCost == stack.recomputedRetainedCost, "cost cache diverged (\(context))")
        #expect(realUndoCount <= model.undoContents.count, "more undo entries than model (\(context))")
        if realUndoCount < model.undoContents.count {
            // Eviction happened — trim the model's forgotten oldest entries.
            model.undoContents.removeFirst(model.undoContents.count - realUndoCount)
        }
    }
}
