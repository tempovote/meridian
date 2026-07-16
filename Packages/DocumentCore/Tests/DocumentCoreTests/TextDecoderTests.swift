import Foundation
import Testing
@testable import DocumentCore

@Test func emptyInputIsUTF8Empty() {
    let decoded = TextDecoder.decode([][...])
    #expect(decoded.buffer.isEmpty)
    #expect(decoded.encoding == .utf8)
    #expect(!decoded.hadBOM)
    #expect(!decoded.repairsMade)
}

@Test func plainUTF8WithoutBOM() {
    let decoded = TextDecoder.decode(Array("tiếng Việt 😀".utf8)[...])
    #expect(decoded.buffer.string == "tiếng Việt 😀")
    #expect(decoded.encoding == .utf8)
    #expect(!decoded.hadBOM)
    #expect(!decoded.repairsMade)
}

@Test func bomOnlyFilesDecodeEmpty() {
    let utf8BOM = TextDecoder.decode([0xEF, 0xBB, 0xBF][...])
    #expect(utf8BOM.buffer.isEmpty)
    #expect(utf8BOM.encoding == .utf8)
    #expect(utf8BOM.hadBOM)
    let utf32LE = TextDecoder.decode([0xFF, 0xFE, 0x00, 0x00][...])
    #expect(utf32LE.buffer.isEmpty)
    #expect(utf32LE.encoding == .utf32LittleEndian, "FF FE 00 00 is UTF-32LE, not UTF-16LE")
    #expect(utf32LE.hadBOM)
}

@Test func utf8BOMWithInvalidPayloadRepairs() {
    let decoded = TextDecoder.decode([0xEF, 0xBB, 0xBF, 0x41, 0xFF][...])
    #expect(decoded.encoding == .utf8)
    #expect(decoded.hadBOM)
    #expect(decoded.repairsMade)
    #expect(decoded.buffer.string == "A\u{FFFD}")
}

/// Round-trip property: encode(includeBOM: true) → decode restores text,
/// encoding, and BOM flag for every Unicode encoding and corpus sample.
@Test func unicodeEncodingsRoundTripThroughDecode() throws {
    let encodings: [TextEncoding] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
    ]
    for encoding in encodings {
        for sample in fuzzCorpus {
            let bytes = try #require(encoding.encode(sample, includeBOM: true))
            let decoded = TextDecoder.decode(bytes[...])
            #expect(decoded.buffer.string == sample)
            #expect(decoded.encoding == encoding)
            #expect(decoded.hadBOM)
            #expect(!decoded.repairsMade)
        }
    }
}

@Test func utf8WithoutBOMRoundTrips() throws {
    for sample in fuzzCorpus {
        let bytes = try #require(TextEncoding.utf8.encode(sample, includeBOM: false))
        let decoded = TextDecoder.decode(bytes[...])
        #expect(decoded.buffer.string == sample)
        #expect(decoded.encoding == .utf8)
        #expect(!decoded.hadBOM)
    }
}

@Test func latin1BytesDetectAndReencode() {
    let bytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9] // "café" in ISO Latin-1 / CP1252
    let decoded = TextDecoder.decode(bytes[...])
    #expect(decoded.buffer.string == "café")
    guard case .legacy = decoded.encoding else {
        Issue.record("expected a legacy encoding, got \(decoded.encoding)")
        return
    }
    #expect(decoded.encoding.encode(decoded.buffer.string, includeBOM: false) == bytes)
    #expect(!decoded.hadBOM)
    #expect(!decoded.repairsMade)
}

@Test func shiftJISBytesDecodeLosslessly() throws {
    let text = "こんにちは、世界。テキストエディタです。"
    let data = try #require(text.data(using: .shiftJIS))
    let bytes = Array(data)
    let decoded = TextDecoder.decode(bytes[...])
    #expect(decoded.buffer.string == text)
    #expect(!decoded.repairsMade)
}

@Test func byteSoupStillDecodes() {
    // Invalid UTF-8, no BOM-shaped prefix: pipeline must not fail or crash.
    let decoded = TextDecoder.decode([0x81, 0xFF, 0x0D, 0xFE, 0x81][...])
    guard case .legacy = decoded.encoding else {
        Issue.record("expected a legacy fallback, got \(decoded.encoding)")
        return
    }
    #expect(decoded.buffer.utf8Count > 0)
}

@Test func latin1FallbackMapsBytesOneToOne() {
    // Force the last-resort path shape: Latin-1 maps byte N to U+00N.
    let text = LegacyEncodingDetector.latin1String([0x41, 0xE9, 0x0A][...])
    #expect(text == "Aé\n")
}

@Test func detectedUnicodeEncodingsMapToTypedCases() {
    #expect(LegacyEncodingDetector.mapDetected(.utf8) == .utf8)
    #expect(LegacyEncodingDetector.mapDetected(.utf16LittleEndian) == .utf16LittleEndian)
    #expect(LegacyEncodingDetector.mapDetected(.utf16) == .utf16BigEndian)
    #expect(LegacyEncodingDetector.mapDetected(.utf32) == .utf32BigEndian)
    #expect(LegacyEncodingDetector.mapDetected(.shiftJIS) == .legacy(.shiftJIS))
}
