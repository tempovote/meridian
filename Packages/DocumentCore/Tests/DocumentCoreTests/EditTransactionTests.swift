import Testing
@testable import DocumentCore

@Test func selectionSetInvariants() {
    let set = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(2), ByteOffset(5) ..< ByteOffset(5)])
    #expect(set.ranges.count == 2)
    #expect(SelectionSet(caretAt: ByteOffset(3)).ranges == [ByteOffset(3) ..< ByteOffset(3)])
    #expect(SelectionSet.empty.ranges.isEmpty)
}

@Test func editFromString() {
    let edit = Edit(range: ByteOffset(1) ..< ByteOffset(3), replacement: "xy")
    #expect(edit.replacement.string == "xy")
    #expect(edit.range == ByteOffset(1) ..< ByteOffset(3))
}

@Test func editEquality() {
    // swiftlint:disable identifier_name
    let a = Edit(range: ByteOffset(0) ..< ByteOffset(1), replacement: "abc")
    let b = Edit(range: ByteOffset(0) ..< ByteOffset(1), replacement: "abc")
    let c = Edit(range: ByteOffset(0) ..< ByteOffset(1), replacement: "abd")
    // swiftlint:enable identifier_name
    #expect(a == b)
    #expect(a != c)
}

@Test func slicingSharesContentAndStartsAtVersionZero() {
    let text = String(repeating: "héllo 😀 world\n", count: 500) // multi-leaf
    let buffer = TextBuffer(text)
    let bytes = Array(text.utf8)
    let lower = scalarBoundary(in: bytes, notAfter: 3000)
    let upper = scalarBoundary(in: bytes, notAfter: 6000)
    let slice = buffer.slicing(ByteOffset(lower) ..< ByteOffset(upper))
    #expect(slice.utf8Count == upper - lower)
    // False positive: this decodes `[UInt8]`, not `Data` (see TextBuffer.swift).
    // swiftlint:disable:next optional_data_string_conversion
    #expect(slice.string == String(decoding: bytes[lower ..< upper], as: UTF8.self))
    #expect(slice.version == BufferVersion(value: 0))
}

@Test func slicingFullAndEmptyRanges() {
    let buffer = TextBuffer("abc")
    #expect(buffer.slicing(ByteOffset(0) ..< ByteOffset(3)).string == "abc")
    #expect(buffer.slicing(ByteOffset(1) ..< ByteOffset(1)).string == "")
    #expect(TextBuffer().slicing(ByteOffset(0) ..< ByteOffset(0)).string == "")
}

@Test func transactionStoresFields() {
    let txn = EditTransaction(
        baseVersion: BufferVersion(value: 7),
        edits: [Edit(range: ByteOffset(0) ..< ByteOffset(0), replacement: "a")],
        selectionBefore: SelectionSet(caretAt: ByteOffset(0)),
        selectionAfter: SelectionSet(caretAt: ByteOffset(1)),
        coalescingKey: .typing,
        origin: .user,
    )
    #expect(txn.baseVersion == BufferVersion(value: 7))
    #expect(txn.edits.count == 1)
    #expect(txn.coalescingKey == .typing)
    #expect(txn.origin == .user)
}

@Test func touchingEditsAreLegal() {
    // upperBound == next lowerBound is allowed (adjacent, non-overlapping).
    let txn = EditTransaction(
        baseVersion: BufferVersion(value: 0),
        edits: [
            Edit(range: ByteOffset(0) ..< ByteOffset(2), replacement: "x"),
            Edit(range: ByteOffset(2) ..< ByteOffset(4), replacement: "y"),
        ],
    )
    #expect(txn.edits.count == 2)
}
