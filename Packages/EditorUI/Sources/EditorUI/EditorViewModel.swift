import DocumentCore
import Observation

/// A single pane's view onto a document: owns this pane's
/// ``TextLayoutEngine`` and per-pane display settings, and delegates all
/// document-level state (buffer, undo history) to a shared
/// ``DocumentModel`` — so multiple panes (e.g. a split editor) can
/// observe/edit the same document independently of their own
/// scroll/selection/display state. Bridges the two mutation paths
/// (ADR 0009): user edits arrive FROM the engine (view led — apply to
/// buffer, record undo, never mirror back); programmatic edits go
/// rope-first THEN mirror into the engine.
@MainActor
@Observable
public final class EditorViewModel {
    @ObservationIgnored public let documentModel: DocumentModel
    @ObservationIgnored private let engine: any TextLayoutEngine

    /// The authoritative document content — a passthrough to `documentModel`.
    public var buffer: TextBuffer {
        documentModel.buffer
    }

    /// Fired when a NEW undo entry is created — a passthrough to
    /// `documentModel.onNewUndoEntry`. See its doc comment for the
    /// coalescing-eviction edge case.
    public var onNewUndoEntry: (() -> Void)? {
        get { documentModel.onNewUndoEntry }
        set { documentModel.onNewUndoEntry = newValue }
    }

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

    /// Loads `documentModel`'s buffer into `engine` and starts observing
    /// its user edits.
    public init(documentModel: DocumentModel, engine: any TextLayoutEngine) {
        self.documentModel = documentModel
        self.engine = engine
        engine.load(buffer: documentModel.buffer)
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

    /// Sets the current selection in the layout engine.
    public func setSelection(_ selection: SelectionSet) {
        engine.setSelection(selection, in: buffer)
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
        documentModel.canUndo
    }

    /// Whether ``redo()`` would change anything.
    public var canRedo: Bool {
        documentModel.canRedo
    }

    /// Applies a programmatic transaction: rope first, then mirror into
    /// the engine. `transaction.baseVersion` must equal the current
    /// buffer version.
    public func perform(_ transaction: EditTransaction) {
        let base = documentModel.perform(transaction)
        engine.apply(transaction, base: base)
    }

    /// Undoes the newest undo entry, mirroring each inverse into the engine.
    public func undo() {
        guard let replayed = documentModel.undo() else { return }
        mirrorIntoEngine(replayed)
    }

    /// Redoes the most recently undone entry.
    public func redo() {
        guard let replayed = documentModel.redo() else { return }
        mirrorIntoEngine(replayed)
    }

    /// Handles an engine-reported user edit: the engine's mirror already
    /// changed, so only `documentModel`'s buffer and undo stack advance here.
    private func userEdited(_ transaction: EditTransaction) {
        _ = documentModel.applyUserEdit(transaction)
    }

    /// Shared by `undo()`/`redo()`: mirrors each replayed transaction into
    /// this pane's engine, in order.
    private func mirrorIntoEngine(_ replayed: [(transaction: EditTransaction, base: TextBuffer)]) {
        for (transaction, base) in replayed {
            engine.apply(transaction, base: base)
        }
    }
}
