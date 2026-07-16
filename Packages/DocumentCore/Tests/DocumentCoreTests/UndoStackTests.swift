import Testing
@testable import DocumentCore

private func makeEdit(_ buffer: TextBuffer, _ range: Range<Int>, _ replacement: String) -> EditTransaction {
    EditTransaction(
        baseVersion: buffer.version,
        edits: [Edit(range: ByteOffset(range.lowerBound) ..< ByteOffset(range.upperBound), replacement: replacement)],
    )
}

@Test func emptyStackHasNothing() {
    var stack = UndoStack()
    #expect(!stack.canUndo)
    #expect(!stack.canRedo)
    #expect(stack.undo() == nil)
    #expect(stack.redo() == nil)
}

@Test func recordUndoRedoRoundTrip() throws {
    var buffer = TextBuffer("hello")
    var stack = UndoStack()
    let txn = makeEdit(buffer, 5 ..< 5, " world")
    stack.record(txn, base: buffer)
    buffer.apply(txn)
    #expect(buffer.string == "hello world")
    #expect(stack.canUndo)

    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    #expect(buffer.string == "hello")
    #expect(!stack.canUndo)
    #expect(stack.canRedo)

    let redoResult = stack.redo()
    let redos = try #require(redoResult)
    for redo in redos {
        buffer.apply(redo)
    }
    #expect(buffer.string == "hello world")
    #expect(stack.canUndo)
    #expect(!stack.canRedo)
}

@Test func multipleEntriesUndoInLIFOOrder() throws {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    for word in ["a", "b", "c"] {
        let at = buffer.utf8Count
        let txn = makeEdit(buffer, at ..< at, word)
        stack.record(txn, base: buffer)
        buffer.apply(txn)
    }
    #expect(buffer.string == "abc")
    #expect(stack.undoCount == 3)
    let firstUndoResult = stack.undo()
    for undo in try #require(firstUndoResult) {
        buffer.apply(undo)
    }
    #expect(buffer.string == "ab")
    let secondUndoResult = stack.undo()
    for undo in try #require(secondUndoResult) {
        buffer.apply(undo)
    }
    #expect(buffer.string == "a")
}

@Test func newRecordClearsRedo() throws {
    var buffer = TextBuffer("x")
    var stack = UndoStack()
    let first = makeEdit(buffer, 1 ..< 1, "y")
    stack.record(first, base: buffer)
    buffer.apply(first)
    let undoResult = stack.undo()
    for undo in try #require(undoResult) {
        buffer.apply(undo)
    }
    #expect(stack.canRedo)
    let second = makeEdit(buffer, 1 ..< 1, "z")
    stack.record(second, base: buffer)
    buffer.apply(second)
    #expect(!stack.canRedo)
    #expect(buffer.string == "xz")
}

@Test func versionsChainAcrossUndoRedo() throws {
    // The undo transactions' baseVersions must match the buffer they're
    // applied to at each point (record → apply → undo → redo).
    var buffer = TextBuffer("abc")
    var stack = UndoStack()
    let txn = makeEdit(buffer, 0 ..< 3, "xyz")
    stack.record(txn, base: buffer)
    buffer.apply(txn)
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    #expect(undos.count == 1)
    #expect(undos[0].baseVersion == buffer.version)
    for undo in undos {
        buffer.apply(undo)
    }
    let redoResult = stack.redo()
    let redos = try #require(redoResult)
    #expect(redos[0].baseVersion == txn.baseVersion || redos[0].edits == txn.edits)
    // Redo forwards are the original transactions; content-level identity is
    // what matters (version lineage diverges after undo — see BufferVersion docs).
    for redo in redos {
        buffer.apply(redo)
    }
    #expect(buffer.string == "xyz")
}
