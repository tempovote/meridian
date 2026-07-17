import Foundation
import Testing
@testable import DocumentCore

private var hugeLineByteCount: Int {
    ProcessInfo.processInfo.environment["MERIDIAN_CORPUS_SCALE"] == "full"
        ? 100 * 1024 * 1024
        : 4 * 1024 * 1024
}

@Test func zwjEmojiSurviveEditsAndConversions() {
    let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦" // 4 scalars + 3 ZWJ, 25 UTF-8 bytes
    var buffer = TextBuffer("a" + family + "b")
    let familyRange = ByteOffset(1) ..< ByteOffset(1 + family.utf8.count)
    #expect(buffer.slice(familyRange) == family)
    // Round-trip every scalar boundary through UTF-16 and back.
    let bytes = Array(buffer.string.utf8)
    for offset in 0 ... bytes.count where buffer.isScalarBoundary(ByteOffset(offset)) {
        let utf16 = buffer.utf16Offset(of: ByteOffset(offset))
        #expect(buffer.byteOffset(of: utf16) == ByteOffset(offset))
    }
    // Deleting the family leaves clean neighbors.
    buffer.replaceSubrange(familyRange, with: "")
    #expect(buffer.string == "ab")
}

@Test func combiningMarkStacksCountCorrectly() {
    let stacked = "e\u{0301}\u{0301}\u{0301}" // e + three combining acutes
    let buffer = TextBuffer(stacked + "\n" + stacked)
    #expect(buffer.utf16Count == 2 * 4 + 1)
    #expect(buffer.lineCount == 2)
    #expect(buffer.byteRange(ofLine: 1).lowerBound == ByteOffset(Array((stacked + "\n").utf8).count))
}

@Test func regionalIndicatorsRoundTrip() {
    let flags = "🇻🇳🇯🇵🇺🇸"
    var buffer = TextBuffer(flags)
    #expect(buffer.utf8Count == flags.utf8.count)
    // Insert between flag pairs (each flag = 2 scalars = 8 bytes).
    buffer.replaceSubrange(ByteOffset(8) ..< ByteOffset(8), with: "|")
    #expect(buffer.string == "🇻🇳|🇯🇵🇺🇸")
}

@Test func crlfSpanningLeavesKeepsLineMapCorrect() {
    let unit = "line\r\n"
    let count = 4000
    let buffer = TextBuffer(String(repeating: unit, count: count))
    #expect(buffer.lineCount == count + 1, "CRLF: only LF terminates a line in byte metadata")
    var rng = SeededRandom(seed: 0x4D31_5043)
    for _ in 0 ..< 50 {
        let line = Int.random(in: 0 ..< count, using: &rng)
        let range = buffer.byteRange(ofLine: line)
        #expect(range.lowerBound.value == line * unit.utf8.count)
        // ADAPTED from the brief: `byteRange(ofLine:)` is documented (and
        // covered by `crlfColumnCountsCRAsOneUnit` in
        // TextBufferConversionsTests.swift) to exclude only the trailing
        // `\n` — the `\r` remains part of the line's content. So the slice
        // of a "line\r\n" unit is "line\r" (5 bytes), not the full 6-byte
        // "line\r\n" the brief assumed.
        #expect(buffer.slice(range) == "line\r")
    }
    let converted = buffer.convertingLineEndings(to: .lf)
    #expect(converted.string == String(repeating: "line\n", count: count))
}

@Test func utf32SurrogatePayloadIsRepaired() {
    // U+D800 as little-endian UTF-32: 00 D8 00 00 — must repair, not crash.
    let result = Transcoder.decodeUTF32([0x00, 0xD8, 0x00, 0x00][...], littleEndian: true)
    #expect(result.text == "\u{FFFD}")
    #expect(result.repairsMade)
}

/// #11's scale case: one line, no newlines, megabytes long (100 MB when
/// MERIDIAN_CORPUS_SCALE=full). The period-12 pattern ("abcdefgh" + 😀 =
/// 12 UTF-8 bytes / 10 UTF-16 units per repeat) makes expected conversion
/// values computable arithmetically — no O(n) String scans per probe.
@Test func hugeSingleLineBehaves() {
    let period = "abcdefgh😀" // 12 UTF-8 bytes, 10 UTF-16 units
    let repeats = hugeLineByteCount / 12
    var buffer = TextBuffer(String(repeating: period, count: repeats))
    let totalBytes = repeats * 12
    #expect(buffer.lineCount == 1)
    #expect(buffer.utf8Count == totalBytes)
    #expect(buffer.utf16Count == repeats * 10)

    var rng = SeededRandom(seed: 0x4D31_5044)
    for _ in 0 ..< 10 {
        let repeatIndex = Int.random(in: 0 ..< repeats, using: &rng)
        let byteOffset = ByteOffset(repeatIndex * 12 + 8) // start of 😀
        let utf16 = buffer.utf16Offset(of: byteOffset)
        #expect(utf16.value == repeatIndex * 10 + 8)
        #expect(buffer.byteOffset(of: utf16) == byteOffset)
        let position = buffer.linePosition(of: byteOffset)
        #expect(position.line == 0)
        #expect(position.utf16Column == repeatIndex * 10 + 8)
    }

    // Edit mid-line: insert + delete keeps counts consistent.
    let mid = ByteOffset((repeats / 2) * 12)
    buffer.replaceSubrange(mid ..< mid, with: "XYZ")
    #expect(buffer.utf8Count == totalBytes + 3)
    #expect(buffer.lineCount == 1)
    buffer.replaceSubrange(mid ..< ByteOffset(mid.value + 3), with: "")
    #expect(buffer.utf8Count == totalBytes)

    // Chunk iteration covers every byte exactly once.
    var covered = 0
    for chunk in buffer.chunks() {
        #expect(chunk.range.lowerBound.value == covered)
        covered += chunk.bytes.count
    }
    #expect(covered == totalBytes)
}
