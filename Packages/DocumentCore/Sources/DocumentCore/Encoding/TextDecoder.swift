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
    public static func decode(_ bytes: ArraySlice<UInt8>) -> DecodedText {
        guard !bytes.isEmpty else {
            return DecodedText(buffer: TextBuffer(), encoding: .utf8, hadBOM: false, repairsMade: false)
        }
        if let (encoding, bomLength) = TextEncoding.sniffBOM(in: bytes) {
            let payload = bytes.dropFirst(bomLength)
            switch encoding {
            case .utf8:
                let isValid = UTF8Validator.validate(payload) == .valid
                let text = isValid ? strictUTF8String(payload) : lossyUTF8String(payload)
                return DecodedText(
                    buffer: TextBuffer(text), encoding: .utf8, hadBOM: true, repairsMade: !isValid,
                )
            case .utf16LittleEndian, .utf16BigEndian:
                let result = Transcoder.decodeUTF16(payload, littleEndian: encoding == .utf16LittleEndian)
                return DecodedText(
                    buffer: TextBuffer(result.text), encoding: encoding,
                    hadBOM: true, repairsMade: result.repairsMade,
                )
            case .utf32LittleEndian, .utf32BigEndian:
                let result = Transcoder.decodeUTF32(payload, littleEndian: encoding == .utf32LittleEndian)
                return DecodedText(
                    buffer: TextBuffer(result.text), encoding: encoding,
                    hadBOM: true, repairsMade: result.repairsMade,
                )
            case .legacy:
                preconditionFailure("sniffBOM never returns a legacy encoding")
            }
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
