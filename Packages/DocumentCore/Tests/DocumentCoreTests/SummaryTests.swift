import Testing
@testable import DocumentCore

@Test func asciiScan() {
    let summary = Summary(scanning: Array("hello\nworld".utf8))
    #expect(summary.utf8 == 11)
    #expect(summary.utf16 == 11)
    #expect(summary.scalars == 11)
    #expect(summary.newlines == 1)
}

@Test func multibyteScan() {
    // "é" U+00E9: 2 UTF-8 bytes, 1 UTF-16 unit. "€" U+20AC: 3 bytes, 1 unit.
    // "😀" U+1F600: 4 bytes, 2 units (surrogate pair).
    let summary = Summary(scanning: Array("é€😀".utf8))
    #expect(summary.utf8 == 2 + 3 + 4)
    #expect(summary.utf16 == 1 + 1 + 2)
    #expect(summary.scalars == 3)
    #expect(summary.newlines == 0)
}

@Test func zwjEmojiCountsScalarsNotGraphemes() {
    // 👨‍👩‍👧 = MAN + ZWJ + WOMAN + ZWJ + GIRL: 5 scalars, 1 grapheme.
    // The rope deliberately counts scalars (ADR 0007).
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    let summary = Summary(scanning: Array(family.utf8))
    #expect(summary.scalars == 5)
    #expect(summary.utf16 == 2 + 1 + 2 + 1 + 2)
}

@Test func crlfCountsOneNewline() {
    // Only LF (0x0A) increments newlines; CRLF therefore counts once.
    let summary = Summary(scanning: Array("a\r\nb".utf8))
    #expect(summary.newlines == 1)
}

@Test func summariesAreAdditive() {
    let whole = Array("abc😀\ndef".utf8)
    // 7 = length of "abc" + "😀" in UTF-8: a scalar boundary between the emoji and "\n".
    let split = 7
    let left = Summary(scanning: whole[..<split])
    let right = Summary(scanning: whole[split...])
    #expect(left + right == Summary(scanning: whole))
}

@Test func matchesFoundationCountsOnMixedText() {
    let text = "Mixed ASCII, tiếng Việt, 日本語, emoji 🎉🎊, and\nnewlines\r\n."
    let summary = Summary(scanning: Array(text.utf8))
    #expect(summary.utf8 == text.utf8.count)
    #expect(summary.utf16 == text.utf16.count)
    #expect(summary.scalars == text.unicodeScalars.count)
    #expect(summary.newlines == text.utf8.count { $0 == 0x0A })
}
