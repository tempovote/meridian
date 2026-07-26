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
    /// Human-readable display name (e.g. "UTF-8", "UTF-16 LE", "Shift-JIS").
    var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .utf32LittleEndian: "UTF-32 LE"
        case .utf32BigEndian: "UTF-32 BE"
        case let .legacy(encoding): String.localizedName(of: encoding)
        }
    }

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

    /// List of standard encodings supported for selection and conversion.
    static var commonEncodings: [TextEncoding] {
        [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32LittleEndian,
            .utf32BigEndian,
            .legacy(.windowsCP1252),
            .legacy(.isoLatin1),
            .legacy(.isoLatin2),
            .legacy(.shiftJIS),
            .legacy(.japaneseEUC),
            .legacy(.macOSRoman),
            .legacy(.ascii),
        ]
    }

    /// Formatted display string including BOM state (e.g. "UTF-8 with BOM" or "UTF-8").
    func formattedDisplayName(includeBOM: Bool) -> String {
        if includeBOM, !byteOrderMark.isEmpty {
            return "\(displayName) with BOM"
        }
        return displayName
    }

    /// Reads macOS `com.apple.TextEncoding` extended file attribute if present.
    static func readXattr(from url: URL) -> TextEncoding? {
        let path = url.path
        let name = "com.apple.TextEncoding"
        let dataSize = getxattr(path, name, nil, 0, 0, 0)
        guard dataSize > 0 else { return nil }
        var data = Data(count: dataSize)
        let result = data.withUnsafeMutableBytes {
            getxattr(path, name, $0.baseAddress, dataSize, 0, 0)
        }
        guard result > 0, let string = String(data: data, encoding: .utf8) else { return nil }
        let parts = string.components(separatedBy: ";")
        guard let firstPart = parts.first, let cfEncodingValue = UInt32(firstPart) else { return nil }
        let nsEncodingRaw = CFStringConvertEncodingToNSStringEncoding(cfEncodingValue)
        guard nsEncodingRaw != 0 else { return nil }
        let nsEncoding = String.Encoding(rawValue: nsEncodingRaw)
        return LegacyEncodingDetector.mapDetected(nsEncoding)
    }

    /// Writes macOS `com.apple.TextEncoding` extended file attribute.
    func writeXattr(to url: URL) {
        let path = url.path
        let name = "com.apple.TextEncoding"
        let nsEncoding: String.Encoding = switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .utf32LittleEndian: .utf32LittleEndian
        case .utf32BigEndian: .utf32BigEndian
        case let .legacy(enc): enc
        }
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(nsEncoding.rawValue)
        let attrValue = "\(cfEncoding);0"
        guard let data = attrValue.data(using: .utf8) else { return }
        data.withUnsafeBytes {
            _ = setxattr(path, name, $0.baseAddress, data.count, 0, 0)
        }
    }
}
