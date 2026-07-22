import DocumentCore
import Observation

/// Owns the document state shared identically across every pane viewing
/// the same document (e.g. both sides of a split editor): the current
/// ``TextBuffer`` snapshot and its ``UndoStack``. Unaware of panes,
/// engines, or display settings — see ``EditorViewModel`` for the
/// per-pane wrapper that owns those and delegates buffer/undo state here.
@MainActor
@Observable
public final class DocumentModel {
    /// The authoritative document content.
    public private(set) var buffer: TextBuffer

    /// Fired when a NEW undo entry is created (coalesced appends do not
    /// fire). The document layer registers one thin `NSUndoManager`
    /// action per callback so menu Undo granularity matches the stack's.
    ///
    /// **Edge case:** If the undo stack evicts the oldest entries to stay
    /// within the 64 MB retained byte budget (which occurs only after ~64 MB
    /// of undo history has accumulated in one session), `undoCount` may
    /// remain unchanged even though a new entry is recorded, suppressing
    /// this callback. This is benign-degraded: `undo()` and `redo()` guard
    /// on `nil` and no-op when there's nothing to undo, so a missed
    /// callback simply means one `NSUndoManager` registration is skipped
    /// (no functional impact on undo/redo behavior, only menu state after
    /// eviction).
    public var onNewUndoEntry: (() -> Void)?

    private var undoStack = UndoStack()

    public init(buffer: TextBuffer) {
        self.buffer = buffer
    }

    /// Whether ``undo()`` would change anything.
    public var canUndo: Bool {
        undoStack.canUndo
    }

    /// Whether ``redo()`` would change anything.
    public var canRedo: Bool {
        undoStack.canRedo
    }

    /// Applies a programmatic transaction to the buffer and undo stack.
    /// `transaction.baseVersion` must equal the current buffer version.
    /// Returns the buffer state immediately before the transaction, for
    /// callers to mirror the same edit into whichever engine(s) render
    /// this document — `DocumentModel` has no notion of panes or engines.
    @discardableResult
    public func perform(_ transaction: EditTransaction) -> TextBuffer {
        applyAndRecord(transaction)
    }

    /// Records a transaction whose content change was already applied
    /// elsewhere (the view-led user-edit path: an engine's own mirror
    /// already changed when the user typed — only the buffer and undo
    /// stack need to advance here). Returns the buffer state immediately
    /// before the transaction, same as ``perform(_:)``.
    ///
    /// Identical in implementation to ``perform(_:)`` today — kept as a
    /// separate, distinctly-documented entry point because the two callers
    /// (`EditorViewModel.perform`/`.userEdited`) diverge in what they do
    /// with the transaction *afterward* (mirroring into this pane's own
    /// engine, or not), which is a real semantic difference at the call
    /// site even though `DocumentModel` itself treats both identically.
    @discardableResult
    public func applyUserEdit(_ transaction: EditTransaction) -> TextBuffer {
        applyAndRecord(transaction)
    }

    private func applyAndRecord(_ transaction: EditTransaction) -> TextBuffer {
        let base = buffer
        buffer.apply(transaction)
        record(transaction, base: base)
        return base
    }

    /// Undoes the newest undo entry. Returns each replayed transaction
    /// paired with the buffer state immediately before *that* transaction
    /// was applied (captured during replay, since `buffer` has moved past
    /// all of them by the time this method returns) — callers mirror each
    /// pair, in order, into whichever engine(s) render this document.
    /// `nil` when there is nothing to undo.
    public func undo() -> [(transaction: EditTransaction, base: TextBuffer)]? {
        guard let transactions = undoStack.undo() else { return nil }
        return replay(transactions)
    }

    /// Redoes the most recently undone entry. See ``undo()`` for the
    /// return value's shape and `nil` case.
    public func redo() -> [(transaction: EditTransaction, base: TextBuffer)]? {
        guard let transactions = undoStack.redo() else { return nil }
        return replay(transactions)
    }

    private func replay(
        _ transactions: [EditTransaction],
    ) -> [(transaction: EditTransaction, base: TextBuffer)] {
        var results: [(transaction: EditTransaction, base: TextBuffer)] = []
        results.reserveCapacity(transactions.count)
        for transaction in transactions {
            let base = buffer
            buffer.apply(transaction)
            results.append((transaction, base))
        }
        return results
    }

    private func record(_ transaction: EditTransaction, base: TextBuffer) {
        let entriesBefore = undoStack.undoCount
        undoStack.record(transaction, base: base)
        if undoStack.undoCount > entriesBefore {
            onNewUndoEntry?()
        }
    }
}
