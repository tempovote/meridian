import DocumentCore
import Testing
@testable import EditorUI

@MainActor
@Suite("DocumentModel")
struct DocumentModelTests {
    @Test func initSeedsBuffer() {
        let model = DocumentModel(buffer: TextBuffer("hello"))
        #expect(model.buffer.string == "hello")
    }

    @Test func performAppliesAndReturnsPreTransactionBase() {
        let model = DocumentModel(buffer: TextBuffer("hello"))
        let baseBefore = model.buffer
        let base = model.perform(EditTransaction(
            baseVersion: baseBefore.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(5), replacement: "goodbye")],
            origin: .replaceAll,
        ))
        #expect(model.buffer.string == "goodbye")
        #expect(base.version == baseBefore.version)
        #expect(base.string == "hello")
    }

    @Test func applyUserEditRecordsAndReturnsBase() {
        let model = DocumentModel(buffer: TextBuffer("hello"))
        let base = model.applyUserEdit(EditTransaction(
            baseVersion: model.buffer.version,
            edits: [Edit(range: ByteOffset(5) ..< ByteOffset(5), replacement: "!")],
            coalescingKey: .typing,
        ))
        #expect(model.buffer.string == "hello!")
        #expect(base.string == "hello")
        #expect(model.canUndo)
    }

    @Test func undoReturnsReplayedTransactionsWithPerStepBase() {
        let model = DocumentModel(buffer: TextBuffer("ab"))
        _ = model.applyUserEdit(EditTransaction(
            baseVersion: model.buffer.version,
            edits: [Edit(range: ByteOffset(2) ..< ByteOffset(2), replacement: "c")],
            coalescingKey: .typing,
        ))
        #expect(model.buffer.string == "abc")
        let replayed = model.undo()
        #expect(model.buffer.string == "ab")
        #expect(replayed?.count == 1)
        #expect(replayed?[0].base.string == "abc")
    }

    @Test func redoReappliesUndoneEntry() {
        let model = DocumentModel(buffer: TextBuffer("ab"))
        _ = model.applyUserEdit(EditTransaction(
            baseVersion: model.buffer.version,
            edits: [Edit(range: ByteOffset(2) ..< ByteOffset(2), replacement: "c")],
            coalescingKey: .typing,
        ))
        _ = model.undo()
        #expect(model.canRedo)
        let replayed = model.redo()
        #expect(model.buffer.string == "abc")
        #expect(replayed?.count == 1)
    }

    @Test func undoWithNothingRecordedIsANoOp() {
        let model = DocumentModel(buffer: TextBuffer("x"))
        #expect(!model.canUndo)
        #expect(model.undo() == nil)
        #expect(model.buffer.string == "x")
    }

    @Test func coalescedTypingFiresOneUndoEntryCallback() {
        let model = DocumentModel(buffer: TextBuffer(""))
        var callbacks = 0
        model.onNewUndoEntry = { callbacks += 1 }
        _ = model.applyUserEdit(EditTransaction(
            baseVersion: model.buffer.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(0), replacement: "a")],
            coalescingKey: .typing,
        ))
        _ = model.applyUserEdit(EditTransaction(
            baseVersion: model.buffer.version,
            edits: [Edit(range: ByteOffset(1) ..< ByteOffset(1), replacement: "b")],
            coalescingKey: .typing,
        ))
        #expect(callbacks == 1)
    }
}
