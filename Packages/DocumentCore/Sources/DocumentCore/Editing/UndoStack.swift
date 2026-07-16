extension EditTransaction {
    /// Returns a copy of `self` with `baseVersion` swapped to `version`;
    /// every other field (`edits`, selections, `coalescingKey`, `origin`) is
    /// unchanged.
    ///
    /// `UndoStack` uses this to replay a recorded step against the live
    /// buffer: the version a step was originally recorded against
    /// (`forward.baseVersion` / `inverse.baseVersion`) drifts from the
    /// buffer's actual version once undo/redo cycles have happened, but
    /// `TextBuffer.apply(_:)` is strict about `version == baseVersion`
    /// matching. Rebasing produces a transaction with identical content
    /// effects, addressed at the version the buffer will actually hold when
    /// the caller applies it.
    func rebased(to version: BufferVersion) -> EditTransaction {
        EditTransaction(
            baseVersion: version,
            edits: edits,
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter,
            coalescingKey: coalescingKey,
            origin: origin,
        )
    }
}

/// One recorded (forward, inverse) pair. An `Entry` holds one or more steps —
/// coalescing and grouping (Task 4) append steps to the newest entry instead
/// of creating a new one.
struct Step: Sendable {
    /// The transaction as originally applied to the live buffer.
    let forward: EditTransaction
    /// `forward.inverted(base:)`, computed eagerly at record time so undo
    /// never has to reconstruct it (and never needs the old buffer content
    /// again — the inverse already carries chunk-shared slices of it).
    let inverse: EditTransaction
    /// Approximate byte cost of retaining this step, for `byteBudget`
    /// eviction (Task 4). Computed now, unused now — see `UndoStack`'s
    /// header comment.
    let cost: Int
}

/// A group of steps that undo/redo together as a single unit. In this task
/// every entry holds exactly one step; `key`/`isGroup`/`isClosed` exist for
/// Task 4's coalescing and stay inert here (every `record` call creates a
/// fresh, single-step entry).
struct Entry: Sendable {
    var steps: [Step]
    /// Wall-clock time of the most recent step, for coalescing windows
    /// (Task 4).
    var lastInstant: ContinuousClock.Instant
    /// The coalescing key steps must share to be appended to this entry
    /// (Task 4).
    var key: CoalescingKey?
    /// Whether this entry represents an explicit multi-transaction group
    /// (Task 4).
    var isGroup: Bool
    /// Whether this entry is no longer eligible to receive more coalesced
    /// steps (Task 4).
    var isClosed: Bool
}

/// Delta-based undo history. Owned by a Document (M3); value type, Sendable.
///
/// An entry holds one or more (forward, inverse) steps — coalescing and
/// grouping append steps to the newest entry (Task 4; every `record` here
/// creates a new single-step entry). Undo returns the inverses in reverse
/// order; the caller applies them in order returned.
///
/// ## Version rebasing
///
/// `TextBuffer.apply(_:)` preconditions `version == transaction.baseVersion`
/// strictly — it never bends that rule. But a step's recorded `forward` and
/// `inverse` carry the `baseVersion` that was live *at record time*; after an
/// undo/redo round trip the live buffer's version has moved past those
/// recorded values (each `apply` bumps the version by exactly one, including
/// undo/redo applies themselves). Replaying a recorded transaction verbatim
/// would therefore trap.
///
/// The fix is bookkeeping, not a relaxed precondition: `UndoStack` tracks
/// `expectedVersion`, the version the live buffer will hold the next time
/// the caller applies something this stack hands back. `record` sets it from
/// the real buffer (`base.version + 1`, the version `apply(transaction)`
/// produces). `undo`/`redo` rebase each returned transaction's `baseVersion`
/// to consecutive values starting at `expectedVersion` (via
/// `EditTransaction.rebased(to:)`, which only swaps `baseVersion` — the
/// edits themselves are untouched) and then advance `expectedVersion` by the
/// number of steps returned, so the next call starts from the version those
/// applies will have produced.
public struct UndoStack: Sendable {
    private var entries: [Entry] = []
    private var redoEntries: [Entry] = []
    /// Retained for Task 4's eviction; not consulted by this task (every
    /// `record` unconditionally appends — see the type header).
    private let byteBudget: Int
    /// The version the live buffer will hold when the caller next applies a
    /// transaction this stack returns. Meaningless while `entries` and
    /// `redoEntries` are both empty (nothing has been recorded yet), so its
    /// initial value is never read.
    private var expectedVersion = BufferVersion(value: 0)

    /// Creates an empty undo stack.
    public init(byteBudget: Int = 64 * 1024 * 1024) {
        self.byteBudget = byteBudget
    }

    /// Records a transaction applied to `base` (the buffer BEFORE
    /// application). Clears the redo stack. `instant` drives coalescing
    /// windows (Task 4).
    ///
    /// - Precondition: `base.version == transaction.baseVersion` (enforced
    ///   by `transaction.inverted(base:)`).
    public mutating func record(
        _ transaction: EditTransaction,
        base: TextBuffer,
        at instant: ContinuousClock.Instant = .now,
    ) {
        let inverse = transaction.inverted(base: base)
        let step = Step(forward: transaction, inverse: inverse, cost: cost(forward: transaction, inverse: inverse))
        entries.append(Entry(
            steps: [step],
            lastInstant: instant,
            key: transaction.coalescingKey,
            isGroup: false,
            isClosed: false,
        ))
        redoEntries.removeAll()
        expectedVersion = BufferVersion(value: base.version.value + 1)
    }

    /// Transactions that undo the newest entry (already inverted, in
    /// application order), or nil if nothing to undo. Moves the entry to
    /// redo.
    ///
    /// Each returned transaction is rebased to the version the buffer will
    /// hold at the point the caller applies it — see the type header.
    public mutating func undo() -> [EditTransaction]? {
        guard let entry = entries.popLast() else { return nil }
        var version = expectedVersion
        var inverses: [EditTransaction] = []
        inverses.reserveCapacity(entry.steps.count)
        for step in entry.steps.reversed() {
            inverses.append(step.inverse.rebased(to: version))
            version = BufferVersion(value: version.value + 1)
        }
        expectedVersion = version
        redoEntries.append(entry)
        return inverses
    }

    /// Transactions that re-apply the most recently undone entry, or nil.
    ///
    /// Each returned transaction is rebased to the version the buffer will
    /// hold at the point the caller applies it — see the type header.
    public mutating func redo() -> [EditTransaction]? {
        guard let entry = redoEntries.popLast() else { return nil }
        var version = expectedVersion
        var forwards: [EditTransaction] = []
        forwards.reserveCapacity(entry.steps.count)
        for step in entry.steps {
            forwards.append(step.forward.rebased(to: version))
            version = BufferVersion(value: version.value + 1)
        }
        expectedVersion = version
        entries.append(entry)
        return forwards
    }

    /// Whether `undo()` would return a non-nil result.
    public var canUndo: Bool {
        !entries.isEmpty
    }

    /// Whether `redo()` would return a non-nil result.
    public var canRedo: Bool {
        !redoEntries.isEmpty
    }

    /// Number of undoable entries (grouped/coalesced steps count once).
    public var undoCount: Int {
        entries.count
    }

    /// Approximate retained-byte cost of a step: both replacements' bytes
    /// plus a fixed per-step overhead, for Task 4's `byteBudget` eviction.
    private func cost(forward: EditTransaction, inverse: EditTransaction) -> Int {
        let forwardBytes = forward.edits.reduce(0) { $0 + $1.replacement.utf8Count }
        let inverseBytes = inverse.edits.reduce(0) { $0 + $1.replacement.utf8Count }
        return forwardBytes + inverseBytes + 64
    }
}
