import Foundation

/// The result of decoding raw file bytes into the editor's internal UTF-8.
public struct DecodedText: Sendable {
    /// The decoded content, at version 0.
    public let buffer: TextBuffer
    /// The detected on-disk encoding — what save re-encodes to (§6.4).
    public let encoding: TextEncoding
    /// True iff the input began with a byte-order mark.
    public let hadBOM: Bool
    /// True iff any U+FFFD substitution was made while decoding.
    public let repairsMade: Bool
}

/// §6.4 open pipeline: BOM sniff → strict UTF-8 validation → statistical
/// legacy detection (Foundation, lossless only) → last-resort ISO Latin-1.
/// Total: every byte sequence decodes to something.
public enum TextDecoder {
    /// Decodes raw file bytes into the editor's internal UTF-8 representation.
    public static func decode(_ bytes: ArraySlice<UInt8>, overrideEncoding: TextEncoding? = nil) -> DecodedText {
        guard !bytes.isEmpty else {
            return DecodedText(
                buffer: TextBuffer(),
                encoding: overrideEncoding ?? .utf8,
                hadBOM: false,
                repairsMade: false,
            )
        }
        if let overrideEncoding {
            let bom = overrideEncoding.byteOrderMark
            let hasBOM = !bom.isEmpty && bytes.count >= bom.count && bytes.prefix(bom.count).elementsEqual(bom)
            let payload = hasBOM ? bytes.dropFirst(bom.count) : bytes
            return decodePayload(payload, forcedEncoding: overrideEncoding, hadBOM: hasBOM)
        }
        if let (encoding, bomLength) = TextEncoding.sniffBOM(in: bytes) {
            let payload = bytes.dropFirst(bomLength)
            return decodePayload(payload, forcedEncoding: encoding, hadBOM: true)
        }
        if UTF8Validator.validate(bytes) == .valid {
            let text = strictUTF8String(bytes)
            return DecodedText(buffer: TextBuffer(text), encoding: .utf8, hadBOM: false, repairsMade: false)
        }
        if let (foundationEncoding, text) = LegacyEncodingDetector.detect(bytes) {
            return DecodedText(
                buffer: TextBuffer(text),
                encoding: LegacyEncodingDetector.mapDetected(foundationEncoding),
                hadBOM: false,
                repairsMade: false,
            )
        }
        let text = LegacyEncodingDetector.latin1String(bytes)
        return DecodedText(
            buffer: TextBuffer(text), encoding: .legacy(.isoLatin1), hadBOM: false, repairsMade: false,
        )
    }

    private static func decodePayload(
        _ payload: ArraySlice<UInt8>, forcedEncoding: TextEncoding, hadBOM: Bool,
    ) -> DecodedText {
        switch forcedEncoding {
        case .utf8:
            let isValid = UTF8Validator.validate(payload) == .valid
            let text = isValid ? strictUTF8String(payload) : lossyUTF8String(payload)
            return DecodedText(buffer: TextBuffer(text), encoding: .utf8, hadBOM: hadBOM, repairsMade: !isValid)
        case .utf16LittleEndian, .utf16BigEndian:
            let result = Transcoder.decodeUTF16(payload, littleEndian: forcedEncoding == .utf16LittleEndian)
            return DecodedText(
                buffer: TextBuffer(result.text),
                encoding: forcedEncoding,
                hadBOM: hadBOM,
                repairsMade: result.repairsMade,
            )
        case .utf32LittleEndian, .utf32BigEndian:
            let result = Transcoder.decodeUTF32(payload, littleEndian: forcedEncoding == .utf32LittleEndian)
            return DecodedText(
                buffer: TextBuffer(result.text),
                encoding: forcedEncoding,
                hadBOM: hadBOM,
                repairsMade: result.repairsMade,
            )
        case let .legacy(foundationEncoding):
            let data = Data(payload)
            if let string = String(data: data, encoding: foundationEncoding) {
                return DecodedText(
                    buffer: TextBuffer(string),
                    encoding: forcedEncoding,
                    hadBOM: false,
                    repairsMade: false,
                )
            }
            let text = LegacyEncodingDetector.latin1String(payload)
            return DecodedText(buffer: TextBuffer(text), encoding: forcedEncoding, hadBOM: false, repairsMade: true)
        }
    }

    /// Decodes bytes already known to be strict, well-formed UTF-8.
    private static func strictUTF8String(_ bytes: ArraySlice<UInt8>) -> String {
        Transcoder.wellFormedUTF8String(bytes)
    }

    /// Decodes bytes that may contain ill-formed UTF-8, substituting U+FFFD
    /// for malformed or truncated sequences (mirrors `Transcoder`'s approach:
    /// run the standard library's `transcode`, which performs the repair,
    /// then hand well-formed bytes to `strictUTF8String`).
    private static func lossyUTF8String(_ bytes: ArraySlice<UInt8>) -> String {
        var repaired = [UInt8]()
        repaired.reserveCapacity(bytes.count)
        _ = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF8.self, stoppingOnError: false) {
            repaired.append($0)
        }
        return strictUTF8String(repaired[...])
    }
}
