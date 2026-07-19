import DocumentCore
import Observation

/// Owns the authoritative document state: the current ``TextBuffer``
/// snapshot and its ``UndoStack``. Bridges the two mutation paths
/// (ADR 0009): user edits arrive FROM the engine (view led — apply to
/// buffer, record undo, never mirror back); programmatic edits go
/// rope-first THEN mirror into the engine.
@MainActor
@Observable
public final class EditorViewModel {
    /// The authoritative document content.
    public private(set) var buffer: TextBuffer

    /// Fired when a NEW undo entry is created (coalesced appends do not
    /// fire). The document layer registers one thin `NSUndoManager`
    /// action per callback so menu Undo granularity matches the stack's.
    ///
    /// **Edge case:** If the undo stack evicts the oldest entries to stay
    /// within the 64 MB retained byte budget (which occurs only after ~64 MB
    /// of undo history has accumulated in one session), `undoCount` may
    /// remain unchanged even though a new entry is recorded, suppressing this
    /// callback. This is benign-degraded: `undo()` and `redo()` guard on nil
    /// and no-op when there's nothing to undo, so a missed callback simply
    /// means one `NSUndoManager` registration is skipped (no functional
    /// impact on undo/redo behavior, only menu state after eviction).
    public var onNewUndoEntry: (() -> Void)?

    /// Whether the line number gutter is visible.
    public var isGutterVisible: Bool = true {
        didSet { engine.setGutterVisible(isGutterVisible) }
    }

    /// Whether soft wrap (line wrapping) is enabled.
    public var isSoftWrapEnabled: Bool = true {
        didSet { engine.setSoftWrap(isSoftWrapEnabled) }
    }

    /// Whether the current caret line background highlight is enabled.
    public var isCurrentLineHighlightEnabled: Bool = true

    /// Whether the status bar at the bottom of the window is visible.
    public var isStatusBarVisible: Bool = true

    private var undoStack = UndoStack()
    @ObservationIgnored private let engine: any TextLayoutEngine

    /// Loads `buffer` into `engine` and starts observing its user edits.
    public init(buffer: TextBuffer, engine: any TextLayoutEngine) {
        self.buffer = buffer
        self.engine = engine
        engine.load(buffer: buffer)
        engine.setSoftWrap(isSoftWrapEnabled)
        engine.setGutterVisible(isGutterVisible)
        engine.onUserEdit = { [weak self] transaction in
            self?.userEdited(transaction)
        }
    }

    /// The current selection in rope coordinates.
    public var selection: SelectionSet {
        engine.selection(in: buffer)
    }

    /// 1-based (line, column) position of the primary cursor caret.
    public var currentCaretLineColumn: (line: Int, column: Int) {
        let offset = selection.ranges.first?.lowerBound ?? ByteOffset(0)
        let pos = buffer.linePosition(of: offset)
        return (line: pos.line + 1, column: pos.utf16Column + 1)
    }

    /// Total number of UTF-16 code units across all active selection ranges.
    public var selectionCharacterCount: Int {
        selection.ranges.reduce(0) { sum, range in
            let start = buffer.utf16Offset(of: range.lowerBound).value
            let end = buffer.utf16Offset(of: range.upperBound).value
            return sum + (end - start)
        }
    }

    /// Total line count in the document.
    public var lineCount: Int {
        buffer.lineCount
    }

    /// Whether ``undo()`` would change anything.
    public var canUndo: Bool {
        undoStack.canUndo
    }

    /// Whether ``redo()`` would change anything.
    public var canRedo: Bool {
        undoStack.canRedo
    }

    /// Applies a programmatic transaction: rope first, then mirror into
    /// the engine. `transaction.baseVersion` must equal the current
    /// buffer version.
    public func perform(_ transaction: EditTransaction) {
        let base = buffer
        buffer.apply(transaction)
        record(transaction, base: base)
        engine.apply(transaction, base: base)
    }

    /// Undoes the newest undo entry, mirroring each inverse into the engine.
    public func undo() {
        guard let transactions = undoStack.undo() else { return }
        replay(transactions)
    }

    /// Redoes the most recently undone entry.
    public func redo() {
        guard let transactions = undoStack.redo() else { return }
        replay(transactions)
    }

    /// Handles an engine-reported user edit: the engine's mirror already
    /// changed, so only the buffer and undo stack advance here.
    private func userEdited(_ transaction: EditTransaction) {
        let base = buffer
        buffer.apply(transaction)
        record(transaction, base: base)
    }

    private func record(_ transaction: EditTransaction, base: TextBuffer) {
        let entriesBefore = undoStack.undoCount
        undoStack.record(transaction, base: base)
        if undoStack.undoCount > entriesBefore {
            onNewUndoEntry?()
        }
    }

    private func replay(_ transactions: [EditTransaction]) {
        for transaction in transactions {
            let base = buffer
            buffer.apply(transaction)
            engine.apply(transaction, base: base)
        }
    }
}
