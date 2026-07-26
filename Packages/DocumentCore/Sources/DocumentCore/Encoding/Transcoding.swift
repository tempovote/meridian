import Foundation

/// Text decoded from a non-UTF-8 Unicode payload.
public struct TranscodingResult: Hashable, Sendable {
    /// The decoded text; malformed input units appear as U+FFFD.
    public let text: String
    /// True iff any U+FFFD substitution was made (invalid or truncated units).
    public let repairsMade: Bool
}

/// Decodes fixed-width Unicode byte payloads (UTF-16, UTF-32) to `String`,
/// substituting U+FFFD for ill-formed or truncated input.
public enum Transcoder {
    /// Decodes UTF-16 bytes (payload AFTER any BOM). An odd trailing byte
    /// becomes U+FFFD with `repairsMade` set; so do unpaired surrogates.
    public static func decodeUTF16(
        _ bytes: ArraySlice<UInt8>, littleEndian: Bool,
    ) -> TranscodingResult {
        var units = [UInt16]()
        units.reserveCapacity(bytes.count / 2 + 1)
        var repairs = false
        var iterator = bytes.makeIterator()
        while let first = iterator.next() {
            guard let second = iterator.next() else {
                units.append(0xFFFD)
                repairs = true
                break
            }
            units.append(
                littleEndian
                    ? UInt16(second) << 8 | UInt16(first)
                    : UInt16(first) << 8 | UInt16(second),
            )
        }
        return finish(units, UTF16.self, hadRepairs: repairs)
    }

    /// Decodes UTF-32 bytes (payload AFTER any BOM). Trailing partial words,
    /// surrogate code points, and values above U+10FFFF become U+FFFD.
    public static func decodeUTF32(
        _ bytes: ArraySlice<UInt8>, littleEndian: Bool,
    ) -> TranscodingResult {
        var units = [UInt32]()
        units.reserveCapacity(bytes.count / 4 + 1)
        var repairs = false
        var word = [UInt8]()
        for byte in bytes {
            word.append(byte)
            if word.count == 4 {
                let value = littleEndian
                    ? word.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    : word.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                units.append(value)
                word.removeAll(keepingCapacity: true)
            }
        }
        if !word.isEmpty {
            units.append(0xFFFD)
            repairs = true
        }
        return finish(units, UTF32.self, hadRepairs: repairs)
    }

    /// Converts well-formed UTF-8 bytes to `String`. Traps if `bytes` is
    /// not valid UTF-8 — every call site in this module guarantees
    /// well-formedness before calling this (either via the standard
    /// library's `transcode`, which always emits well-formed UTF-8, or via
    /// prior explicit validation), so this is a loud signal of a real bug
    /// rather than a silent empty-string fallback.
    ///
    /// `String(bytes:encoding:)` is used instead of the equivalent
    /// `String(decoding:as:)` because SwiftLint's
    /// `optional_data_string_conversion` matches on that call's syntax
    /// alone, with no way to tell a raw byte source apart from `Data`.
    static func wellFormedUTF8String(_ bytes: some Sequence<UInt8>) -> String {
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            preconditionFailure("bytes were not valid UTF-8, but the caller guaranteed well-formedness")
        }
        return string
    }

    /// Runs the standard-library `transcode` from `codec` to UTF-8, folding
    /// its own U+FFFD substitution flag together with `hadRepairs` (repairs
    /// already detected while assembling `units`, e.g. truncated trailing
    /// bytes).
    private static func finish<Codec: UnicodeCodec>(
        _ units: [Codec.CodeUnit], _ codec: Codec.Type, hadRepairs: Bool,
    ) -> TranscodingResult {
        var utf8Bytes = [UInt8]()
        utf8Bytes.reserveCapacity(units.count * 4)
        let hadErrors = transcode(
            units.makeIterator(), from: codec, to: UTF8.self, stoppingOnError: false,
        ) { utf8Bytes.append($0) }
        return TranscodingResult(
            text: wellFormedUTF8String(utf8Bytes),
            repairsMade: hadRepairs || hadErrors,
        )
    }
}

public extension TextEncoding {
    /// Encodes `text` into this encoding, optionally prefixing the BOM
    /// (no-op for legacy encodings — they have none). Returns nil only when
    /// a legacy encoding cannot represent `text` losslessly.
    func encode(_ text: String, includeBOM: Bool) -> [UInt8]? {
        var out: [UInt8] = includeBOM ? byteOrderMark : []
        switch self {
        case .utf8:
            out.append(contentsOf: text.utf8)
        case .utf16LittleEndian, .utf16BigEndian:
            let little = self == .utf16LittleEndian
            out.reserveCapacity(out.count + text.utf16.count * 2)
            for unit in text.utf16 {
                let high = UInt8(truncatingIfNeeded: unit >> 8)
                let low = UInt8(truncatingIfNeeded: unit)
                out.append(little ? low : high)
                out.append(little ? high : low)
            }
        case .utf32LittleEndian, .utf32BigEndian:
            let little = self == .utf32LittleEndian
            for scalar in text.unicodeScalars {
                let value = scalar.value
                let bigEndianBytes: [UInt8] = [
                    UInt8(truncatingIfNeeded: value >> 24),
                    UInt8(truncatingIfNeeded: value >> 16),
                    UInt8(truncatingIfNeeded: value >> 8),
                    UInt8(truncatingIfNeeded: value),
                ]
                out.append(contentsOf: little ? bigEndianBytes.reversed() : bigEndianBytes)
            }
        case let .legacy(encoding):
            guard let data = text.data(using: encoding, allowLossyConversion: false) else {
                return nil
            }
            out.append(contentsOf: data)
        }
        return out
    }
}
