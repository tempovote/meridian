import Testing
@testable import DocumentCore

@Test func byteOffsetOrdering() {
    #expect(ByteOffset(3) < ByteOffset(7))
    #expect(ByteOffset(7) == ByteOffset(7))
    #expect(ByteOffset(0) <= ByteOffset(0))
}

@Test func utf16OffsetOrdering() {
    #expect(UTF16Offset(1) < UTF16Offset(2))
    #expect(UTF16Offset(5) == UTF16Offset(5))
}

@Test func offsetTypesAreDistinct() {
    // Compile-time check by construction: a Range<ByteOffset> cannot be built
    // from UTF16Offset bounds. Runtime assertion just anchors the test.
    let range: Range<ByteOffset> = ByteOffset(0) ..< ByteOffset(4)
    #expect(range.contains(ByteOffset(3)))
    #expect(!range.contains(ByteOffset(4)))
}

@Test func linePositionEquality() {
    let pos1 = LinePosition(line: 2, utf16Column: 10)
    let pos2 = LinePosition(line: 2, utf16Column: 10)
    #expect(pos1 == pos2)
    #expect(pos1 != LinePosition(line: 2, utf16Column: 11))
}
