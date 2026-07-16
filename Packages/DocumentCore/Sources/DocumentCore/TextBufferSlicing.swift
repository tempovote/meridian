public extension TextBuffer {
    /// A new buffer containing `range`'s bytes; shares rope chunks with
    /// `self` (O(log n), no byte copying). The slice starts at version 0.
    ///
    /// - Precondition: `range` lies within `0..<utf8Count` (inclusive of
    ///   `utf8Count` at the upper bound) and both endpoints land on scalar
    ///   boundaries.
    func slicing(_ range: Range<ByteOffset>) -> TextBuffer {
        precondition(
            range.lowerBound.value >= 0 && range.upperBound.value <= utf8Count,
            "slicing range out of bounds",
        )
        precondition(
            isScalarBoundary(range.lowerBound) && isScalarBoundary(range.upperBound),
            "slicing range must fall on scalar boundaries",
        )
        let (_, rest) = root.split(at: range.lowerBound.value)
        let (middle, _) = rest.split(at: range.upperBound.value - range.lowerBound.value)
        return TextBuffer(root: middle)
    }
}
