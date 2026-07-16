import Testing
@testable import DocumentCore

@Test func acceptsWellFormedText() {
    let samples = [
        "",
        "hello",
        "tiếng Việt — 日本語テキスト",
        "😀👨\u{200D}👩\u{200D}👧🇻🇳",
        "é́́", // stacked combining marks
        String(repeating: "abcdefgh", count: 100), // exercises the word fast path
    ]
    for sample in samples {
        #expect(UTF8Validator.validate(Array(sample.utf8)[...]) == .valid, "\(sample.prefix(20))")
    }
}

@Test func rejectsLoneContinuationBytes() {
    #expect(UTF8Validator.validate([0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0x61, 0xBF][...]) == .invalid(firstInvalidByte: ByteOffset(1)))
}

@Test func rejectsOverlongForms() {
    // 0xC0/0xC1 can only start overlong 2-byte forms; 0xE0 0x80 is overlong 3-byte.
    #expect(UTF8Validator.validate([0xC0, 0xAF][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0xC1, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0xE0, 0x80, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0xF0, 0x80, 0x80, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
}

@Test func rejectsSurrogates() {
    // U+D800 encoded as UTF-8 (CESU-8): ED A0 80.
    #expect(UTF8Validator.validate([0xED, 0xA0, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
}

@Test func rejectsAboveMaxCodePoint() {
    // F4 90 80 80 would be U+110000; F5+ can never start a sequence.
    #expect(UTF8Validator.validate([0xF4, 0x90, 0x80, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0xF5, 0x80, 0x80, 0x80][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
    #expect(UTF8Validator.validate([0xFF][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
}

@Test func rejectsTruncatedSequences() {
    #expect(UTF8Validator.validate([0xE2, 0x82][...]) == .invalid(firstInvalidByte: ByteOffset(0))) // € cut short
    let tail: [UInt8] = [0x6F, 0x6B, 0xF0, 0x9F] // "ok" + truncated emoji
    #expect(UTF8Validator.validate(tail[...]) == .invalid(firstInvalidByte: ByteOffset(2)))
}

@Test func rejectsBadContinuationMidSequence() {
    // 3-byte lead, valid second byte, ASCII third byte.
    #expect(UTF8Validator.validate([0xE2, 0x82, 0x41][...]) == .invalid(firstInvalidByte: ByteOffset(0)))
}

@Test func reportsOffsetAfterFastPathRun() {
    var bytes = [UInt8](repeating: 0x61, count: 64)
    bytes.append(0x80)
    #expect(UTF8Validator.validate(bytes[...]) == .invalid(firstInvalidByte: ByteOffset(64)))
}

@Test func offsetsAreRelativeToSliceStart() {
    let bytes: [UInt8] = [0x80, 0x80, 0x80, 0x61, 0x80]
    // Slice starting at index 3: "a" then a lone continuation at relative offset 1.
    #expect(UTF8Validator.validate(bytes[3...]) == .invalid(firstInvalidByte: ByteOffset(1)))
}

@Test func agreesWithFuzzCorpusRoundTrips() {
    var rng = SeededRandom(seed: 0x4D31_5034)
    for _ in 0 ..< 200 {
        var text = ""
        for _ in 0 ..< 10 {
            text += fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
        }
        #expect(UTF8Validator.validate(Array(text.utf8)[...]) == .valid)
    }
}
