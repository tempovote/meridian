/// True when `index` is a valid split point in `bytes`: start, end, or a
/// scalar-leading byte (never a UTF-8 continuation byte).
func isScalarBoundary(_ bytes: [UInt8], _ index: Int) -> Bool {
    index == 0 || index == bytes.count || bytes[index] & 0xC0 != 0x80
}

/// The nearest scalar boundary at or before `index`.
func scalarBoundary(in bytes: [UInt8], notAfter index: Int) -> Int {
    var pos = index
    while pos > 0, !isScalarBoundary(bytes, pos) {
        pos -= 1
    }
    return pos
}

/// A rope leaf: an owned UTF-8 chunk with cached summary. Immutable after
/// construction — edits build new leaves.
struct Leaf: Sendable {
    static let maxBytes = 2048
    static let minBytes = 512

    let bytes: [UInt8]
    let summary: Summary

    init(bytes: [UInt8]) {
        self.bytes = bytes
        summary = Summary(scanning: bytes)
    }

    /// Splits a byte string into leaves of at most `maxBytes`, never
    /// splitting inside a scalar. Aims for evenly sized leaves.
    static func leaves(from bytes: [UInt8]) -> [Leaf] {
        guard !bytes.isEmpty else { return [] }
        var result: [Leaf] = []
        var start = 0
        while start < bytes.count {
            let idealEnd = min(start + maxBytes, bytes.count)
            var end = scalarBoundary(in: bytes, notAfter: idealEnd)
            if end <= start {
                end = idealEnd // degenerate: oversized scalar run, take as-is
            }
            result.append(Leaf(bytes: Array(bytes[start ..< end])))
            start = end
        }
        return result
    }
}
