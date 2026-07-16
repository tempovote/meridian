import Testing
@testable import DocumentCore

private let start = ContinuousClock.now

private func typing(_ buffer: TextBuffer, at offset: Int, _ text: String) -> EditTransaction {
    EditTransaction(
        baseVersion: buffer.version,
        edits: [Edit(range: ByteOffset(offset) ..< ByteOffset(offset), replacement: text)],
        coalescingKey: .typing,
    )
}

@Test func typingCoalescesWithinWindow() throws {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    for (index, ch) in ["h", "e", "y"].enumerated() {
        let txn = typing(buffer, at: buffer.utf8Count, ch)
        stack.record(txn, base: buffer, at: start + .milliseconds(200 * index))
        buffer.apply(txn)
    }
    #expect(buffer.string == "hey")
    #expect(stack.undoCount == 1, "three keystrokes coalesce into one entry")
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    #expect(buffer.string == "")
}

@Test func typingGapBreaksCoalescing() {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    let first = typing(buffer, at: 0, "a")
    stack.record(first, base: buffer, at: start)
    buffer.apply(first)
    let second = typing(buffer, at: 1, "b")
    stack.record(second, base: buffer, at: start + .seconds(2))
    buffer.apply(second)
    #expect(stack.undoCount == 2)
}

@Test func nonAdjacentTypingDoesNotCoalesce() {
    var buffer = TextBuffer("abcdef")
    var stack = UndoStack()
    let first = typing(buffer, at: 6, "x")
    stack.record(first, base: buffer, at: start)
    buffer.apply(first)
    let second = typing(buffer, at: 0, "y") // caret jumped — not adjacent
    stack.record(second, base: buffer, at: start + .milliseconds(100))
    buffer.apply(second)
    #expect(stack.undoCount == 2)
}

@Test func deletingCoalescesBackspaces() throws {
    var buffer = TextBuffer("abc")
    var stack = UndoStack()
    for step in 0 ..< 3 {
        let end = buffer.utf8Count
        let txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(end - 1) ..< ByteOffset(end), replacement: "")],
            coalescingKey: .deleting,
        )
        stack.record(txn, base: buffer, at: start + .milliseconds(100 * step))
        buffer.apply(txn)
    }
    #expect(buffer.string == "")
    #expect(stack.undoCount == 1)
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    #expect(buffer.string == "abc")
}

@Test func differentKeysDoNotCoalesce() {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    let insert = typing(buffer, at: 0, "ab")
    stack.record(insert, base: buffer, at: start)
    buffer.apply(insert)
    let delete = EditTransaction(
        baseVersion: buffer.version,
        edits: [Edit(range: ByteOffset(1) ..< ByteOffset(2), replacement: "")],
        coalescingKey: .deleting,
    )
    stack.record(delete, base: buffer, at: start + .milliseconds(50))
    buffer.apply(delete)
    #expect(stack.undoCount == 2)
}

@Test func groupWrapsMultipleRecordsIntoOneEntry() throws {
    var buffer = TextBuffer("one two three")
    var stack = UndoStack()
    stack.beginGroup()
    for _ in 0 ..< 2 {
        // replace first 3 bytes twice (replace-all style repeated edits)
        let txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(3), replacement: "XXX")],
        )
        stack.record(txn, base: buffer)
        buffer.apply(txn)
    }
    stack.endGroup()
    #expect(stack.undoCount == 1)
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    #expect(buffer.string == "one two three")
}

@Test func recordAfterEndGroupStartsNewEntry() {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    stack.beginGroup()
    let inGroup = typing(buffer, at: 0, "a")
    stack.record(inGroup, base: buffer, at: start)
    buffer.apply(inGroup)
    stack.endGroup()
    let after = typing(buffer, at: 1, "b") // would coalesce if group were open
    stack.record(after, base: buffer, at: start + .milliseconds(10))
    buffer.apply(after)
    #expect(stack.undoCount == 2)
}

@Test func evictionDropsOldestBeyondBudget() {
    var buffer = TextBuffer("")
    var stack = UndoStack(byteBudget: 4096)
    for index in 0 ..< 8 {
        let chunk = String(repeating: "x", count: 1024)
        let at = buffer.utf8Count
        let txn = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(at) ..< ByteOffset(at), replacement: chunk)],
        )
        stack.record(txn, base: buffer, at: start + .seconds(10 * index)) // no coalescing
        buffer.apply(txn)
    }
    #expect(stack.undoCount < 8, "old entries evicted")
    #expect(stack.undoCount >= 1, "newest entry never evicted")
    #expect(stack.retainedCost <= 4096 + 2048, "cost roughly bounded by budget")
}

@Test func undoBreaksCoalescingChain() throws {
    var buffer = TextBuffer("")
    var stack = UndoStack()
    let first = typing(buffer, at: 0, "a")
    stack.record(first, base: buffer, at: start)
    buffer.apply(first)
    let undoResult = stack.undo()
    let undos = try #require(undoResult)
    for undo in undos {
        buffer.apply(undo)
    }
    let redoResult = stack.redo()
    let redos = try #require(redoResult)
    for redo in redos {
        buffer.apply(redo)
    }
    let second = typing(buffer, at: 1, "b")
    stack.record(second, base: buffer, at: start + .milliseconds(10))
    buffer.apply(second)
    #expect(stack.undoCount == 2, "no coalescing across an undo/redo boundary")
}
