/// Result of a strict UTF-8 validation pass.
public enum UTF8ValidationResult: Hashable, Sendable {
    case valid
    /// Offset of the lead byte of the first malformed sequence, relative to
    /// the start of the validated slice.
    case invalid(firstInvalidByte: ByteOffset)
}

/// Strict RFC 3629 validation: rejects overlong forms, CESU-8-encoded
/// surrogates, code points above U+10FFFF, and truncated sequences.
/// ASCII runs are consumed 8 bytes at a time (word-wise high-bit test).
public enum UTF8Validator {
    public static func validate(_ bytes: ArraySlice<UInt8>) -> UTF8ValidationResult {
        bytes.withUnsafeBufferPointer { validate($0) }
    }

    // swiftlint:disable cyclomatic_complexity
    private static func validate(_ buffer: UnsafeBufferPointer<UInt8>) -> UTF8ValidationResult {
        let count = buffer.count
        let raw = UnsafeRawBufferPointer(buffer)
        var index = 0
        while index < count {
            let lead = buffer[index]
            if lead < 0x80 {
                index += 1
                // ASCII fast path: consume 8 bytes at a time while no high bit is set.
                while index + 8 <= count {
                    let word = raw.loadUnaligned(fromByteOffset: index, as: UInt64.self)
                    if word & 0x8080_8080_8080_8080 != 0 {
                        break
                    }
                    index += 8
                }
                continue
            }
            let sequenceLength: Int
            let secondByteRange: ClosedRange<UInt8>
            switch lead {
            case 0xC2 ... 0xDF: sequenceLength = 2; secondByteRange = 0x80 ... 0xBF
            case 0xE0: sequenceLength = 3; secondByteRange = 0xA0 ... 0xBF
            case 0xE1 ... 0xEC, 0xEE, 0xEF: sequenceLength = 3; secondByteRange = 0x80 ... 0xBF
            case 0xED: sequenceLength = 3; secondByteRange = 0x80 ... 0x9F
            case 0xF0: sequenceLength = 4; secondByteRange = 0x90 ... 0xBF
            case 0xF1 ... 0xF3: sequenceLength = 4; secondByteRange = 0x80 ... 0xBF
            case 0xF4: sequenceLength = 4; secondByteRange = 0x80 ... 0x8F
            default: return .invalid(firstInvalidByte: ByteOffset(index))
            }
            guard index + sequenceLength <= count, secondByteRange.contains(buffer[index + 1]) else {
                return .invalid(firstInvalidByte: ByteOffset(index))
            }
            // swiftformat:disable wrapMultilineStatementBraces
            for continuation in (index + 2) ..< (index + sequenceLength)
                where !(0x80 ... 0xBF).contains(buffer[continuation]) {
                return .invalid(firstInvalidByte: ByteOffset(index))
            }
            // swiftformat:enable wrapMultilineStatementBraces
            index += sequenceLength
        }
        return .valid
    }
    // swiftlint:enable cyclomatic_complexity
}
