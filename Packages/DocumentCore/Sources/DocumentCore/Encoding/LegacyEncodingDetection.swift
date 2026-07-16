import Foundation

/// Statistical legacy-encoding detection via Foundation (§6.4). Internal —
/// the public entry point is `TextDecoder.decode`.
enum LegacyEncodingDetector {
    /// Runs Foundation's statistical encoding detector over `bytes`.
    ///
    /// Returns nil when Foundation finds no lossless interpretation.
    static func detect(_ bytes: ArraySlice<UInt8>) -> (encoding: String.Encoding, text: String)? {
        var converted: NSString?
        var usedLossy: ObjCBool = false
        let raw = NSString.stringEncoding(
            for: Data(bytes),
            encodingOptions: [.allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: &usedLossy,
        )
        guard raw != 0, let converted, !usedLossy.boolValue else { return nil }
        return (String.Encoding(rawValue: raw), converted as String)
    }

    /// Folds Foundation Unicode results into the typed cases (unmarked
    /// endian → big-endian, Unicode's default).
    static func mapDetected(_ encoding: String.Encoding) -> TextEncoding {
        switch encoding {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian, .utf16: .utf16BigEndian
        case .utf32LittleEndian: .utf32LittleEndian
        case .utf32BigEndian, .utf32: .utf32BigEndian
        default: .legacy(encoding)
        }
    }

    /// ISO Latin-1 is total: byte N is exactly U+00N.
    static func latin1String(_ bytes: ArraySlice<UInt8>) -> String {
        var text = ""
        text.reserveCapacity(bytes.count)
        for byte in bytes {
            text.unicodeScalars.append(Unicode.Scalar(byte))
        }
        return text
    }
}
