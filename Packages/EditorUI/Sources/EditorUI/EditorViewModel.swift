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

    /// Fired after any transaction changes `documentModel`'s buffer via
    /// this pane — a user edit in this pane's engine, a programmatic
    /// `perform`, or an undo/redo replay this pane originated. The owning
    /// document uses this to mirror the same transaction (content-only,
    /// selection untouched) into any sibling pane's engine when the
    /// document is split into more than one pane.
    public var onDidApplyTransaction: ((EditTransaction, TextBuffer) -> Void)?

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

    /// Folds the innermost foldable region containing the caret line.
    public func foldAtCaret() {
        engine.foldAtCaret()
    }

    /// Unfolds at the caret: innermost folded region containing the caret.
    public func unfoldAtCaret() {
        engine.unfoldAtCaret()
    }

    public func foldAll() {
        engine.foldAll()
    }

    public func unfoldAll() {
        engine.unfoldAll()
    }

    /// Spec Fold Level N semantics (fold depth==n, unfold shallower).
    public func foldLevel(_ level: Int) {
        engine.foldLevel(level)
    }

    /// Menu validation: is there a foldable region at the caret?
    public var canFoldAtCaret: Bool {
        engine.canFoldAtCaret
    }

    /// Menu validation: is there something to unfold at the caret?
    public var canUnfoldAtCaret: Bool {
        engine.canUnfoldAtCaret
    }

    /// Menu validation: are there foldable regions in the document?
    public var canFoldAll: Bool {
        engine.canFoldAll
    }

    /// Menu validation: are there folded regions in the document?
    public var canUnfoldAll: Bool {
        engine.canUnfoldAll
    }

    /// Applies a programmatic transaction: rope first, then mirror into
    /// the engine. `transaction.baseVersion` must equal the current
    /// buffer version.
    public func perform(_ transaction: EditTransaction) {
        let base = documentModel.perform(transaction)
        engine.apply(transaction, base: base)
        onDidApplyTransaction?(transaction, base)
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
        let base = documentModel.applyUserEdit(transaction)
        onDidApplyTransaction?(transaction, base)
    }

    /// Shared by `undo()`/`redo()`: mirrors each replayed transaction into
    /// this pane's engine, in order, firing `onDidApplyTransaction` for
    /// each so the owning document can mirror it into any sibling pane too.
    private func mirrorIntoEngine(_ replayed: [(transaction: EditTransaction, base: TextBuffer)]) {
        for (transaction, base) in replayed {
            engine.apply(transaction, base: base)
            onDidApplyTransaction?(transaction, base)
        }
    }
}
