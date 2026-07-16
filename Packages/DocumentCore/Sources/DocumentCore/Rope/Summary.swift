/// Additive metadata for a span of UTF-8 bytes: summaries of adjacent spans
/// sum to the summary of the whole. Counts Unicode scalars, not grapheme
/// clusters — grapheme counts are not additive across chunk boundaries
/// (ADR 0007); grapheme handling belongs to the cursor layer.
struct Summary: Equatable {
    var utf8: Int
    var utf16: Int
    var scalars: Int
    var newlines: Int

    static let zero = Summary(utf8: 0, utf16: 0, scalars: 0, newlines: 0)

    init(utf8: Int, utf16: Int, scalars: Int, newlines: Int) {
        self.utf8 = utf8
        self.utf16 = utf16
        self.scalars = scalars
        self.newlines = newlines
    }

    /// Scans a UTF-8 byte span. The span must begin and end on scalar
    /// boundaries (callers uphold this; leaves never split scalars).
    init(scanning bytes: some Collection<UInt8>) {
        var utf8 = 0
        var utf16 = 0
        var scalars = 0
        var newlines = 0
        for byte in bytes {
            utf8 += 1
            if byte == 0x0A {
                newlines += 1
            }
            if byte & 0xC0 != 0x80 { // scalar-leading byte (not a continuation)
                scalars += 1
                utf16 += byte >= 0xF0 ? 2 : 1 // 4-byte scalars need a surrogate pair
            }
        }
        self.init(utf8: utf8, utf16: utf16, scalars: scalars, newlines: newlines)
    }

    static func + (lhs: Summary, rhs: Summary) -> Summary {
        Summary(
            utf8: lhs.utf8 + rhs.utf8,
            utf16: lhs.utf16 + rhs.utf16,
            scalars: lhs.scalars + rhs.scalars,
            newlines: lhs.newlines + rhs.newlines,
        )
    }

    static func += (lhs: inout Summary, rhs: Summary) {
        lhs = lhs + rhs
    }
}
