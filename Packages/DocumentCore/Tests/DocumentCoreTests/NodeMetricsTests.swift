import Testing
@testable import DocumentCore

private let sample = "héllo 😀\nworld\r\nsecond 🇻🇳 line\n\ntail"

@Test func utf16LengthMatchesFoundation() {
    let bytes = Array(sample.utf8)
    let node = Node.build(from: bytes)
    for prefix in 0 ... bytes.count where isScalarBoundary(bytes, prefix) {
        // False positive: this decodes `[UInt8]`, not `Data` (see TextBuffer.swift).
        // swiftlint:disable:next optional_data_string_conversion
        let expected = String(decoding: bytes[..<prefix], as: UTF8.self).utf16.count
        #expect(node.utf16Length(upToByte: prefix) == expected, "prefix \(prefix)")
    }
}

@Test func byteLengthInvertsUTF16Length() {
    let bytes = Array(sample.utf8)
    let node = Node.build(from: bytes)
    for prefix in 0 ... bytes.count where isScalarBoundary(bytes, prefix) {
        let units = node.utf16Length(upToByte: prefix)
        #expect(node.byteLength(upToUTF16: units) == prefix)
    }
}

@Test func lineStartsMatchNaiveScan() {
    let bytes = Array(sample.utf8)
    let node = Node.build(from: bytes)
    var expectedStarts = [0]
    for (index, byte) in bytes.enumerated() where byte == 0x0A {
        expectedStarts.append(index + 1)
    }
    #expect(node.summary.newlines + 1 == expectedStarts.count)
    for (line, start) in expectedStarts.enumerated() {
        #expect(node.byteOffsetOfLineStart(line) == start, "line \(line)")
    }
}

@Test func newlinesBeforeMatchesNaiveScan() {
    let bytes = Array(sample.utf8)
    let node = Node.build(from: bytes)
    for prefix in 0 ... bytes.count {
        let expected = bytes[..<prefix].count { $0 == 0x0A }
        #expect(node.newlines(beforeByte: prefix) == expected, "prefix \(prefix)")
    }
}

/// Multi-leaf property test: random mixed text large enough for a real tree,
/// primitives compared against naive reference computations at random boundaries.
@Test func primitivesMatchReferenceOnLargeMixedText() {
    var rng = SeededRandom(seed: 0x4D31_5032)
    var text = ""
    for _ in 0 ..< 800 {
        text += fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
    }
    let bytes = Array(text.utf8)
    let node = Node.build(from: bytes)
    #expect(node.height >= 1)
    for _ in 0 ..< 200 {
        let prefix = randomScalarBoundary(in: bytes, using: &rng)
        // False positive: this decodes `[UInt8]`, not `Data` (see TextBuffer.swift).
        // swiftlint:disable:next optional_data_string_conversion
        let str = String(decoding: bytes[..<prefix], as: UTF8.self)
        #expect(node.utf16Length(upToByte: prefix) == str.utf16.count)
        #expect(node.byteLength(upToUTF16: str.utf16.count) == prefix)
        #expect(node.newlines(beforeByte: prefix) == bytes[..<prefix].count { $0 == 0x0A })
    }
    for line in stride(from: 0, through: node.summary.newlines, by: max(1, node.summary.newlines / 50)) {
        var seen = 0
        var expected = 0
        if line > 0 {
            var count = 0
            for (index, byte) in bytes.enumerated() where byte == 0x0A {
                count += 1
                if count == line {
                    expected = index + 1
                    break
                }
            }
            seen = expected
        }
        #expect(node.byteOffsetOfLineStart(line) == seen, "line \(line)")
    }
}
