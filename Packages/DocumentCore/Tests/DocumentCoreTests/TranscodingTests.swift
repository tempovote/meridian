import Testing
@testable import DocumentCore

@Test func decodesUTF16BothEndians() {
    // "A😀" = U+0041, U+1F600 (surrogates D83D DE00).
    let littleEndian: [UInt8] = [0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE]
    let bigEndian: [UInt8] = [0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00]
    let le = Transcoder.decodeUTF16(littleEndian[...], littleEndian: true)
    let be = Transcoder.decodeUTF16(bigEndian[...], littleEndian: false)
    #expect(le == TranscodingResult(text: "A😀", repairsMade: false))
    #expect(be == TranscodingResult(text: "A😀", repairsMade: false))
}

@Test func decodesUTF32BothEndians() {
    // "A😀" = U+0041, U+1F600.
    let littleEndian: [UInt8] = [0x41, 0x00, 0x00, 0x00, 0x00, 0xF6, 0x01, 0x00]
    let bigEndian: [UInt8] = [0x00, 0x00, 0x00, 0x41, 0x00, 0x01, 0xF6, 0x00]
    let le = Transcoder.decodeUTF32(littleEndian[...], littleEndian: true)
    let be = Transcoder.decodeUTF32(bigEndian[...], littleEndian: false)
    #expect(le == TranscodingResult(text: "A😀", repairsMade: false))
    #expect(be == TranscodingResult(text: "A😀", repairsMade: false))
}

@Test func emptyPayloadDecodesToEmpty() {
    #expect(Transcoder.decodeUTF16([][...], littleEndian: true) == TranscodingResult(text: "", repairsMade: false))
    #expect(Transcoder.decodeUTF32([][...], littleEndian: false) == TranscodingResult(text: "", repairsMade: false))
}

@Test func oddTrailingByteIsRepaired() {
    let bytes: [UInt8] = [0x41, 0x00, 0x42] // "A" + half a unit
    let result = Transcoder.decodeUTF16(bytes[...], littleEndian: true)
    #expect(result.text == "A\u{FFFD}")
    #expect(result.repairsMade)
}

@Test func unpairedSurrogateIsRepaired() {
    let bytes: [UInt8] = [0x3D, 0xD8, 0x41, 0x00] // lone high surrogate, then "A"
    let result = Transcoder.decodeUTF16(bytes[...], littleEndian: true)
    #expect(result.text.contains("\u{FFFD}"))
    #expect(result.text.hasSuffix("A"))
    #expect(result.repairsMade)
}

@Test func utf32OutOfRangeIsRepaired() {
    let tooBig: [UInt8] = [0x00, 0x00, 0x11, 0x00] // U+110000 little-endian
    let result = Transcoder.decodeUTF32(tooBig[...], littleEndian: true)
    #expect(result.text == "\u{FFFD}")
    #expect(result.repairsMade)
    let truncated: [UInt8] = [0x41, 0x00] // half a word
    let short = Transcoder.decodeUTF32(truncated[...], littleEndian: true)
    #expect(short.text == "\u{FFFD}")
    #expect(short.repairsMade)
}

@Test func encodeUnicodeEncodingsWithAndWithoutBOM() throws {
    let text = "Aé😀"
    for encoding in [
        TextEncoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
    ] {
        let plain = try #require(encoding.encode(text, includeBOM: false))
        let bommed = try #require(encoding.encode(text, includeBOM: true))
        #expect(bommed == encoding.byteOrderMark + plain)
        #expect(!plain.isEmpty)
    }
    #expect(try #require(TextEncoding.utf8.encode(text, includeBOM: false)) == Array(text.utf8))
}

@Test func encodeDecodePairsAreInverse() throws {
    let text = "tiếng Việt 😀\r\nline"
    let utf16 = try #require(TextEncoding.utf16BigEndian.encode(text, includeBOM: false))
    #expect(Transcoder.decodeUTF16(utf16[...], littleEndian: false).text == text)
    let utf32 = try #require(TextEncoding.utf32LittleEndian.encode(text, includeBOM: false))
    #expect(Transcoder.decodeUTF32(utf32[...], littleEndian: true).text == text)
}

@Test func legacyEncodeIsLosslessOrNil() {
    let latin1 = TextEncoding.legacy(.isoLatin1)
    #expect(latin1.encode("café", includeBOM: false) == [0x63, 0x61, 0x66, 0xE9])
    #expect(latin1.encode("café", includeBOM: true) == [0x63, 0x61, 0x66, 0xE9], "BOM is a no-op for legacy")
    #expect(latin1.encode("😀", includeBOM: false) == nil, "unrepresentable must be nil, not lossy")
}
