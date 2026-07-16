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
/// coalescing and grouping append steps to the newest entry instead of
/// creating a new one.
struct Step: Sendable {
    /// The transaction as originally applied to the live buffer.
    let forward: EditTransaction
    /// `forward.inverted(base:)`, computed eagerly at record time so undo
    /// never has to reconstruct it (and never needs the old buffer content
    /// again — the inverse already carries chunk-shared slices of it).
    let inverse: EditTransaction
    /// Approximate byte cost of retaining this step, for `byteBudget`
    /// eviction.
    let cost: Int
}

/// A group of steps that undo/redo together as a single unit.
struct Entry: Sendable {
    var steps: [Step]
    /// Wall-clock time of the most recent step, for coalescing windows.
    var lastInstant: ContinuousClock.Instant
    /// The coalescing key steps must share to be appended to this entry.
    var key: CoalescingKey?
    /// Whether this entry represents an explicit multi-transaction group.
    var isGroup: Bool
    /// Whether this entry is no longer eligible to receive more coalesced
    /// steps (an undo happened, or an explicit group was closed).
    var isClosed: Bool
}

/// Delta-based undo history. Owned by a Document (M3); value type, Sendable.
///
/// An entry holds one or more (forward, inverse) steps. Three mechanisms
/// append a step to the newest entry instead of creating a new one:
///
/// - **Typing/deleting coalescing**: consecutive `record` calls whose
///   transactions are both single-edit pure inserts (or both single-edit
///   pure deletes), share the same `coalescingKey`, land within
///   `coalescingWindow` of each other, and are byte-adjacent (see
///   `coalesces(_:into:at:)`) merge into the top entry's steps.
/// - **Explicit groups** (`beginGroup()`/`endGroup()`): every `record` call
///   while a group is open appends unconditionally, ignoring keys/adjacency/
///   time.
/// - Coalescing never crosses an **undo boundary**: `undo()` marks the
///   popped entry closed before moving it to `redoEntries`, so redoing it
///   later can never silently absorb a subsequent keystroke.
///
/// Undo returns the inverses in reverse order; the caller applies them in
/// order returned.
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
    /// Maximum retained cost (see `retainedCost`) before `record` starts
    /// evicting the oldest entries.
    private let byteBudget: Int
    /// The version the live buffer will hold when the caller next applies a
    /// transaction this stack returns. Meaningless while `entries` and
    /// `redoEntries` are both empty (nothing has been recorded yet), so its
    /// initial value is never read.
    private var expectedVersion = BufferVersion(value: 0)
    /// Whether `beginGroup()` has been called without a matching
    /// `endGroup()` yet.
    private var isGroupOpen = false

    /// Coalescing (typing/deleting) only merges consecutive records within
    /// this wall-clock gap; a larger gap between keystrokes starts a new
    /// entry.
    private static let coalescingWindow: ContinuousClock.Duration = .seconds(1)

    /// Creates an empty undo stack.
    public init(byteBudget: Int = 64 * 1024 * 1024) {
        self.byteBudget = byteBudget
    }

    /// Records a transaction applied to `base` (the buffer BEFORE
    /// application). Clears the redo stack. `instant` drives coalescing
    /// windows.
    ///
    /// If a group is open (`beginGroup()`), the resulting step is appended
    /// unconditionally to the open group's entry. Otherwise, if the top
    /// entry is open (not closed by a prior `undo()`/`redo()` or a closed
    /// group) and `transaction` coalesces with its last step (see
    /// `coalesces(_:into:at:)`), the step is appended there too. In every
    /// other case a new entry is created. After appending, the oldest
    /// entries are evicted while `retainedCost` exceeds `byteBudget`.
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
        expectedVersion = BufferVersion(value: base.version.value + 1)
        redoEntries.removeAll()

        if let topIndex = entries.indices.last {
            let top = entries[topIndex]
            if top.isGroup, !top.isClosed {
                entries[topIndex].steps.append(step)
                entries[topIndex].lastInstant = instant
                evict()
                return
            }
            if !top.isClosed, coalesces(transaction, into: top, at: instant) {
                entries[topIndex].steps.append(step)
                entries[topIndex].lastInstant = instant
                evict()
                return
            }
        }

        entries.append(Entry(
            steps: [step],
            lastInstant: instant,
            key: transaction.coalescingKey,
            isGroup: false,
            isClosed: false,
        ))
        evict()
    }

    /// Opens an explicit group: subsequent `record` calls append to a single
    /// entry, ignoring coalescing keys, adjacency, and time, until
    /// `endGroup()`.
    ///
    /// - Precondition: no group is already open.
    public mutating func beginGroup() {
        precondition(!isGroupOpen, "beginGroup() called while a group is already open")
        isGroupOpen = true
        entries.append(Entry(steps: [], lastInstant: .now, key: nil, isGroup: true, isClosed: false))
    }

    /// Closes the group opened by `beginGroup()`. If no records were made
    /// while the group was open, no entry is retained; otherwise the
    /// group's entry is closed (no further coalescing into it).
    ///
    /// - Precondition: a group is open.
    public mutating func endGroup() {
        precondition(isGroupOpen, "endGroup() called with no group open")
        isGroupOpen = false
        guard let topIndex = entries.indices.last, entries[topIndex].isGroup, !entries[topIndex].isClosed else {
            preconditionFailure("endGroup() found no open group entry")
        }
        if entries[topIndex].steps.isEmpty {
            entries.removeLast()
        } else {
            entries[topIndex].isClosed = true
        }
    }

    /// Transactions that undo the newest entry (already inverted, in
    /// application order), or nil if nothing to undo. Moves the entry to
    /// redo, closing it so a subsequent `record` cannot coalesce into it
    /// even if `redo()` restores it later.
    ///
    /// Each returned transaction is rebased to the version the buffer will
    /// hold at the point the caller applies it — see the type header.
    public mutating func undo() -> [EditTransaction]? {
        guard var entry = entries.popLast() else { return nil }
        entry.isClosed = true
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
    /// The restored entry stays closed, so a subsequent `record` starts a
    /// fresh entry rather than coalescing into it.
    ///
    /// Each returned transaction is rebased to the version the buffer will
    /// hold at the point the caller applies it — see the type header.
    public mutating func redo() -> [EditTransaction]? {
        guard var entry = redoEntries.popLast() else { return nil }
        entry.isClosed = true
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

    /// Total byte cost currently retained across all undoable entries (for
    /// tests/diagnostics and for `byteBudget` eviction).
    public var retainedCost: Int {
        entries.reduce(0) { total, entry in
            total + entry.steps.reduce(0) { $0 + $1.cost }
        }
    }

    /// Whether `transaction` (about to be recorded at `instant`) may append
    /// as a coalesced step to `entry`, the current top entry.
    ///
    /// Requires: `entry` and `transaction` share a non-nil coalescing key,
    /// `instant` is within `coalescingWindow` of `entry.lastInstant`, both
    /// `transaction` and `entry`'s last step are single-edit, and — per the
    /// shared key — either both edits are pure inserts landing byte-adjacent
    /// (`.typing`) or both are pure deletes landing byte-adjacent
    /// (`.deleting`).
    private func coalesces(
        _ transaction: EditTransaction,
        into entry: Entry,
        at instant: ContinuousClock.Instant,
    ) -> Bool {
        guard let key = entry.key, key == transaction.coalescingKey else { return false }
        guard let prevStep = entry.steps.last else { return false }
        guard instant - entry.lastInstant <= Self.coalescingWindow else { return false }
        guard transaction.edits.count == 1, prevStep.forward.edits.count == 1 else { return false }
        let newEdit = transaction.edits[0]
        let prevEdit = prevStep.forward.edits[0]
        switch key {
        case .typing:
            guard newEdit.range.isEmpty, prevEdit.range.isEmpty else { return false }
            return newEdit.range.lowerBound.value == prevEdit.range.lowerBound.value + prevEdit.replacement.utf8Count
        case .deleting:
            guard newEdit.replacement.utf8Count == 0, prevEdit.replacement.utf8Count == 0 else { return false }
            return newEdit.range.upperBound == prevEdit.range.lowerBound
        }
    }

    /// Drops the oldest entries while the retained cost exceeds
    /// `byteBudget`, always leaving at least the newest entry in place.
    private mutating func evict() {
        while retainedCost > byteBudget, entries.count > 1 {
            entries.removeFirst()
        }
    }

    /// Approximate retained-byte cost of a step: both replacements' bytes
    /// plus a fixed per-step overhead, for `byteBudget` eviction.
    private func cost(forward: EditTransaction, inverse: EditTransaction) -> Int {
        let forwardBytes = forward.edits.reduce(0) { $0 + $1.replacement.utf8Count }
        let inverseBytes = inverse.edits.reduce(0) { $0 + $1.replacement.utf8Count }
        return forwardBytes + inverseBytes + 64
    }
}
