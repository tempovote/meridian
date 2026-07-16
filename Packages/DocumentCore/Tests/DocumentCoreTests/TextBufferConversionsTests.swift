import Testing
@testable import DocumentCore

@Test func byteUTF16RoundTripOnMixedText() {
    let text = "héllo 😀\nworld\r\nsecond 🇻🇳 line\n\ntail"
    let buffer = TextBuffer(text)
    let bytes = Array(text.utf8)
    for prefix in 0 ... bytes.count where isScalarBoundary(bytes, prefix) {
        let utf16 = buffer.utf16Offset(of: ByteOffset(prefix))
        // False positive: this decodes `[UInt8]`, not `Data` (see TextBuffer.swift).
        // swiftlint:disable:next optional_data_string_conversion
        #expect(utf16.value == String(decoding: bytes[..<prefix], as: UTF8.self).utf16.count)
        #expect(buffer.byteOffset(of: utf16) == ByteOffset(prefix))
    }
}

@Test func linePositionOfByteOffset() {
    let buffer = TextBuffer("ab\ncdé\n😀f")
    #expect(buffer.linePosition(of: ByteOffset(0)) == LinePosition(line: 0, utf16Column: 0))
    #expect(buffer.linePosition(of: ByteOffset(2)) == LinePosition(line: 0, utf16Column: 2))
    #expect(buffer.linePosition(of: ByteOffset(3)) == LinePosition(line: 1, utf16Column: 0))
    // "cdé" = c d é(2 bytes): byte 7 = after é, col 3 (é is 1 UTF-16 unit)
    #expect(buffer.linePosition(of: ByteOffset(7)) == LinePosition(line: 1, utf16Column: 3))
    // line 2: "😀f" — after 😀 (4 bytes from line start 8) col = 2 (surrogate pair)
    #expect(buffer.linePosition(of: ByteOffset(12)) == LinePosition(line: 2, utf16Column: 2))
}

@Test func byteOffsetOfLinePosition() {
    let buffer = TextBuffer("ab\ncdé\n😀f")
    #expect(buffer.byteOffset(of: LinePosition(line: 0, utf16Column: 0)) == ByteOffset(0))
    #expect(buffer.byteOffset(of: LinePosition(line: 1, utf16Column: 3)) == ByteOffset(7))
    #expect(buffer.byteOffset(of: LinePosition(line: 2, utf16Column: 2)) == ByteOffset(12))
    // Column pointing at the line's end (the LF) is legal:
    #expect(buffer.byteOffset(of: LinePosition(line: 0, utf16Column: 2)) == ByteOffset(2))
}

@Test func byteRangeOfLineExcludesLF() {
    let buffer = TextBuffer("ab\ncdé\n😀f")
    #expect(buffer.byteRange(ofLine: 0) == ByteOffset(0) ..< ByteOffset(2))
    #expect(buffer.byteRange(ofLine: 1) == ByteOffset(3) ..< ByteOffset(7))
    #expect(buffer.byteRange(ofLine: 2) == ByteOffset(8) ..< ByteOffset(13))
}

@Test func trailingNewlineYieldsEmptyFinalLine() {
    let buffer = TextBuffer("ab\n")
    #expect(buffer.lineCount == 2)
    #expect(buffer.byteRange(ofLine: 1) == ByteOffset(3) ..< ByteOffset(3))
    #expect(buffer.linePosition(of: ByteOffset(3)) == LinePosition(line: 1, utf16Column: 0))
}

@Test func crlfColumnCountsCRAsOneUnit() {
    let buffer = TextBuffer("ab\r\ncd")
    // CR is part of line 0's content (only LF terminates).
    #expect(buffer.byteRange(ofLine: 0) == ByteOffset(0) ..< ByteOffset(3))
    #expect(buffer.linePosition(of: ByteOffset(3)) == LinePosition(line: 0, utf16Column: 3))
    #expect(buffer.linePosition(of: ByteOffset(4)) == LinePosition(line: 1, utf16Column: 0))
}

@Test func derivedDirectionsCompose() {
    let text = "héllo 😀\nworld\r\nsecond line\n\ntail"
    let buffer = TextBuffer(text)
    let bytes = Array(text.utf8)
    for prefix in 0 ... bytes.count where isScalarBoundary(bytes, prefix) {
        let byte = ByteOffset(prefix)
        let viaLine = buffer.utf16Offset(of: buffer.linePosition(of: byte))
        #expect(viaLine == buffer.utf16Offset(of: byte))
        let back = buffer.linePosition(of: buffer.utf16Offset(of: byte))
        #expect(back == buffer.linePosition(of: byte))
    }
}

@Test func conversionsOnEmptyBuffer() {
    let buffer = TextBuffer()
    #expect(buffer.utf16Offset(of: ByteOffset(0)) == UTF16Offset(0))
    #expect(buffer.byteOffset(of: UTF16Offset(0)) == ByteOffset(0))
    #expect(buffer.linePosition(of: ByteOffset(0)) == LinePosition(line: 0, utf16Column: 0))
    #expect(buffer.byteRange(ofLine: 0) == ByteOffset(0) ..< ByteOffset(0))
}

/// Property test across a large mixed buffer: all six directions vs String reference.
@Test func allDirectionsMatchReferenceOnLargeText() {
    var rng = SeededRandom(seed: 0x4D31_5033)
    var text = ""
    for _ in 0 ..< 600 {
        text += fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
    }
    let buffer = TextBuffer(text)
    let bytes = Array(text.utf8)
    for _ in 0 ..< 150 {
        let prefix = randomScalarBoundary(in: bytes, using: &rng)
        // False positive: this decodes `[UInt8]`, not `Data` (see TextBuffer.swift).
        // swiftlint:disable:next optional_data_string_conversion
        let str = String(decoding: bytes[..<prefix], as: UTF8.self)
        let byte = ByteOffset(prefix)
        let utf16 = buffer.utf16Offset(of: byte)
        #expect(utf16.value == str.utf16.count)
        #expect(buffer.byteOffset(of: utf16) == byte)
        let expectedLine = bytes[..<prefix].count { $0 == 0x0A }
        let position = buffer.linePosition(of: byte)
        #expect(position.line == expectedLine)
        #expect(buffer.byteOffset(of: position) == byte)
        #expect(buffer.linePosition(of: utf16) == position)
        #expect(buffer.utf16Offset(of: position) == utf16)
    }
}
