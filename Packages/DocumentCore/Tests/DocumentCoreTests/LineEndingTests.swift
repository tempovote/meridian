import Testing
@testable import DocumentCore

@Test func countsEachStyleOnce() {
    let stats = TextBuffer("a\nb\r\nc\rd").lineEndingStats()
    #expect(stats.lfCount == 1)
    #expect(stats.crlfCount == 1)
    #expect(stats.crCount == 1)
}

@Test func crlfIsNeverDoubleCounted() {
    let stats = TextBuffer("\r\n\r\n\r\n").lineEndingStats()
    #expect(stats.crlfCount == 3)
    #expect(stats.lfCount == 0)
    #expect(stats.crCount == 0)
}

@Test func trailingLoneCRCounts() {
    let stats = TextBuffer("abc\r").lineEndingStats()
    #expect(stats.crCount == 1)
    #expect(stats.crlfCount == 0)
}

@Test func dominantPicksMaxWithLFWinningTies() {
    #expect(TextBuffer("a\nb\r\nc\r\n").lineEndingStats().dominant == .crlf)
    #expect(TextBuffer("a\nb\r\n").lineEndingStats().dominant == .lf, "tie prefers lf")
    #expect(TextBuffer("a\rb\r\n").lineEndingStats().dominant == .crlf, "crlf beats cr on tie")
    #expect(TextBuffer("no breaks here").lineEndingStats().dominant == nil)
    #expect(TextBuffer().lineEndingStats().dominant == nil)
}

@Test func crlfSpanningChunkBoundariesCountsCorrectly() {
    // 6-byte period vs power-of-two leaf sizes guarantees some CRLF pairs
    // straddle leaf boundaries in a multi-leaf rope.
    let buffer = TextBuffer(String(repeating: "line\r\n", count: 2000))
    let stats = buffer.lineEndingStats()
    #expect(stats.crlfCount == 2000)
    #expect(stats.lfCount == 0)
    #expect(stats.crCount == 0)
}

@Test func convertsMixedEndingsToLF() {
    let converted = TextBuffer("a\r\nb\rc\nd").convertingLineEndings(to: .lf)
    #expect(converted.string == "a\nb\nc\nd")
    #expect(converted.version == BufferVersion(value: 0))
}

@Test func convertsToCRLFAndCR() {
    #expect(TextBuffer("a\nb\r\nc\r").convertingLineEndings(to: .crlf).string == "a\r\nb\r\nc\r\n")
    #expect(TextBuffer("a\nb").convertingLineEndings(to: .cr).string == "a\rb")
}

@Test func conversionPreservesMultibyteContent() {
    let text = "tiếng Việt 😀\r\n日本語\rline👨\u{200D}👩\u{200D}👧\n"
    let converted = TextBuffer(text).convertingLineEndings(to: .lf)
    #expect(converted.string == "tiếng Việt 😀\n日本語\nline👨\u{200D}👩\u{200D}👧\n")
}

@Test func conversionAcrossChunkBoundaries() {
    let big = TextBuffer(String(repeating: "line\r\n", count: 2000))
    let converted = big.convertingLineEndings(to: .lf)
    #expect(converted.string == String(repeating: "line\n", count: 2000))
    let stats = converted.lineEndingStats()
    #expect(stats.lfCount == 2000)
    #expect(stats.crlfCount == 0)
}

@Test func conversionIsIdempotent() {
    let source = TextBuffer("a\r\nb\rc\nd")
    let once = source.convertingLineEndings(to: .crlf)
    let twice = once.convertingLineEndings(to: .crlf)
    #expect(once.string == twice.string)
}

@Test func statsAndConversionAgreeOnRandomMixes() {
    var rng = SeededRandom(seed: 0x4D31_5036)
    let breaks = ["\n", "\r\n", "\r"]
    for _ in 0 ..< 50 {
        var text = ""
        var expected = (lf: 0, crlf: 0, cr: 0)
        for _ in 0 ..< 200 {
            text += "x"
            switch Int.random(in: 0 ..< 3, using: &rng) {
            case 0: text += breaks[0]; expected.lf += 1
            case 1: text += breaks[1]; expected.crlf += 1
            default: text += breaks[2]; expected.cr += 1
            }
        }
        let stats = TextBuffer(text).lineEndingStats()
        #expect(stats.lfCount == expected.lf)
        #expect(stats.crlfCount == expected.crlf)
        #expect(stats.crCount == expected.cr)
        let total = expected.lf + expected.crlf + expected.cr
        let converted = TextBuffer(text).convertingLineEndings(to: .lf)
        #expect(converted.lineEndingStats().lfCount == total)
    }
}

@Test func adjacentBreaksCountAndConvertCorrectly() {
    let stats = TextBuffer("\r\r\n\r").lineEndingStats()
    #expect(stats.crCount == 2)
    #expect(stats.crlfCount == 1)
    #expect(stats.lfCount == 0)
    #expect(TextBuffer("\r\r").convertingLineEndings(to: .lf).string == "\n\n")
    #expect(TextBuffer("a\r\r\nb").convertingLineEndings(to: .crlf).string == "a\r\n\r\nb")
}
