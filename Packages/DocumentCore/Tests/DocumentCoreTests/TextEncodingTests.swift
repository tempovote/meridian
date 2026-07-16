import Testing
@testable import DocumentCore

@Test func bomBytesPerEncoding() {
    #expect(TextEncoding.utf8.byteOrderMark == [0xEF, 0xBB, 0xBF])
    #expect(TextEncoding.utf16LittleEndian.byteOrderMark == [0xFF, 0xFE])
    #expect(TextEncoding.utf16BigEndian.byteOrderMark == [0xFE, 0xFF])
    #expect(TextEncoding.utf32LittleEndian.byteOrderMark == [0xFF, 0xFE, 0x00, 0x00])
    #expect(TextEncoding.utf32BigEndian.byteOrderMark == [0x00, 0x00, 0xFE, 0xFF])
    #expect(TextEncoding.legacy(.isoLatin1).byteOrderMark.isEmpty)
}

@Test func sniffsEachBOMFollowedByContent() {
    let cases: [(TextEncoding, [UInt8])] = [
        (.utf8, [0xEF, 0xBB, 0xBF]),
        (.utf16LittleEndian, [0xFF, 0xFE]),
        (.utf16BigEndian, [0xFE, 0xFF]),
        (.utf32BigEndian, [0x00, 0x00, 0xFE, 0xFF]),
    ]
    for (encoding, bom) in cases {
        let hit = TextEncoding.sniffBOM(in: (bom + [0x41, 0x42])[...])
        #expect(hit?.encoding == encoding)
        #expect(hit?.bomLength == bom.count)
    }
}

@Test func utf32BOMWinsOverUTF16Prefix() {
    let utf32 = TextEncoding.sniffBOM(in: [0xFF, 0xFE, 0x00, 0x00][...])
    #expect(utf32?.encoding == .utf32LittleEndian)
    #expect(utf32?.bomLength == 4)
    // Same two lead bytes but a non-NUL third byte: genuine UTF-16LE.
    let utf16 = TextEncoding.sniffBOM(in: [0xFF, 0xFE, 0x41, 0x00][...])
    #expect(utf16?.encoding == .utf16LittleEndian)
    #expect(utf16?.bomLength == 2)
}

@Test func bareUTF16LEBOMSniffsAsUTF16() {
    // Only two bytes total — cannot be a UTF-32 BOM.
    let hit = TextEncoding.sniffBOM(in: [0xFF, 0xFE][...])
    #expect(hit?.encoding == .utf16LittleEndian)
}

@Test func noBOMReturnsNil() {
    #expect(TextEncoding.sniffBOM(in: [][...]) == nil)
    #expect(TextEncoding.sniffBOM(in: [0x68, 0x69][...]) == nil) // "hi"
    #expect(TextEncoding.sniffBOM(in: [0xEF, 0xBB][...]) == nil) // truncated UTF-8 BOM
    #expect(TextEncoding.sniffBOM(in: [0xFE][...]) == nil)
    #expect(TextEncoding.sniffBOM(in: [0x00, 0x00, 0xFE][...]) == nil)
}

@Test func legacyEncodingEquality() {
    #expect(TextEncoding.legacy(.shiftJIS) == TextEncoding.legacy(.shiftJIS))
    #expect(TextEncoding.legacy(.shiftJIS) != TextEncoding.legacy(.isoLatin1))
    #expect(TextEncoding.utf8 != TextEncoding.legacy(.utf8))
}
