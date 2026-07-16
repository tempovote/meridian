import Foundation

/// The on-disk encoding of a document. Internally all text is UTF-8 (§6.4);
/// this type records what to re-encode to on save.
public enum TextEncoding: Hashable, Sendable {
    /// UTF-8 encoding.
    case utf8
    /// UTF-16 little-endian encoding.
    case utf16LittleEndian
    /// UTF-16 big-endian encoding.
    case utf16BigEndian
    /// UTF-32 little-endian encoding.
    case utf32LittleEndian
    /// UTF-32 big-endian encoding.
    case utf32BigEndian
    /// A legacy (non-Unicode) encoding identified by Foundation
    /// (e.g. `.isoLatin1`, `.windowsCP1252`, `.shiftJIS`).
    case legacy(String.Encoding)
}

public extension TextEncoding {
    /// This encoding's byte-order mark; empty for legacy encodings.
    var byteOrderMark: [UInt8] {
        switch self {
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
        case .legacy: []
        }
    }

    /// Identifies a leading BOM. Longest match wins: `FF FE 00 00` is
    /// UTF-32LE, never UTF-16LE followed by a NUL. Returns nil when no BOM.
    static func sniffBOM(
        in bytes: ArraySlice<UInt8>,
    ) -> (encoding: TextEncoding, bomLength: Int)? {
        // Longest match first: FF FE 00 00 (UTF-32LE) must beat FF FE (UTF-16LE).
        let candidates: [TextEncoding] = [
            .utf32LittleEndian, .utf32BigEndian, .utf8, .utf16LittleEndian, .utf16BigEndian,
        ]
        for encoding in candidates {
            let bom = encoding.byteOrderMark
            if bytes.count >= bom.count, bytes.prefix(bom.count).elementsEqual(bom) {
                return (encoding, bom.count)
            }
        }
        return nil
    }
}
