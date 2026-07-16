/// Coordinate conversions between `TextBuffer`'s three offset spaces: UTF-8
/// bytes (`ByteOffset`, the rope-native representation), UTF-16 code units
/// (`UTF16Offset`, for `NSRange`/TextKit interop), and line/column
/// (`LinePosition`, for editor UI).
///
/// The four "primitive" directions (byte<->utf16, byte<->line/column) each
/// descend the rope once, in O(log n), via the `Node` metrics primitives.
/// The two "derived" directions (utf16<->line/column) compose two primitive
/// conversions through a `ByteOffset` and, in debug builds, `assert` that the
/// round trip lands back on the input.
public extension TextBuffer {
    /// Converts a byte offset to the UTF-16 offset of the same position.
    ///
    /// - Precondition: `offset` lies within `0...utf8Count` and falls on a
    ///   Unicode scalar boundary.
    func utf16Offset(of offset: ByteOffset) -> UTF16Offset {
        precondition(
            (0 ... utf8Count).contains(offset.value),
            "utf16Offset(of:) byteOffset \(offset.value) out of range 0...\(utf8Count)",
        )
        precondition(
            isScalarBoundary(offset),
            "utf16Offset(of:) byteOffset \(offset.value) is not a scalar boundary",
        )
        return UTF16Offset(root.utf16Length(upToByte: offset.value))
    }

    /// Converts a UTF-16 offset to the byte offset of the same position.
    ///
    /// - Precondition: `offset` lies within `0...utf16Count` and does not
    ///   land inside a surrogate pair.
    func byteOffset(of offset: UTF16Offset) -> ByteOffset {
        precondition(
            (0 ... utf16Count).contains(offset.value),
            "byteOffset(of:) utf16Offset \(offset.value) out of range 0...\(utf16Count)",
        )
        // The surrogate-pair check happens inside `byteLength(upToUTF16:)`
        // (it needs a leaf scan to detect), which preconditions with a
        // message naming the offending UTF-16 value.
        return ByteOffset(root.byteLength(upToUTF16: offset.value))
    }

    /// Converts a byte offset to its line/column position: the line is the
    /// number of `\n` bytes strictly before `offset`, and the column is
    /// `offset`'s UTF-16 distance from the start of that line.
    ///
    /// - Precondition: `offset` lies within `0...utf8Count` and falls on a
    ///   Unicode scalar boundary.
    func linePosition(of offset: ByteOffset) -> LinePosition {
        precondition(
            (0 ... utf8Count).contains(offset.value),
            "linePosition(of:) byteOffset \(offset.value) out of range 0...\(utf8Count)",
        )
        precondition(
            isScalarBoundary(offset),
            "linePosition(of:) byteOffset \(offset.value) is not a scalar boundary",
        )
        let line = root.newlines(beforeByte: offset.value)
        let lineStartUTF16 = root.utf16Length(upToByte: root.byteOffsetOfLineStart(line))
        let column = root.utf16Length(upToByte: offset.value) - lineStartUTF16
        return LinePosition(line: line, utf16Column: column)
    }

    /// Converts a line/column position to the byte offset of the same
    /// position.
    ///
    /// - Precondition: `position.line` lies within `0..<lineCount` and
    ///   `position.utf16Column` does not exceed the line's UTF-16 length
    ///   (a column equal to that length points at the line's trailing `\n`,
    ///   or at the end of the buffer for the final line, and is legal).
    func byteOffset(of position: LinePosition) -> ByteOffset {
        precondition(
            (0 ..< lineCount).contains(position.line),
            "byteOffset(of:) line \(position.line) out of range 0..<\(lineCount)",
        )
        precondition(
            position.utf16Column >= 0,
            "byteOffset(of:) utf16Column \(position.utf16Column) must be non-negative",
        )
        let lineStart = root.byteOffsetOfLineStart(position.line)
        let targetUTF16 = root.utf16Length(upToByte: lineStart) + position.utf16Column
        precondition(
            targetUTF16 <= utf16Count,
            "byteOffset(of:) utf16Column \(position.utf16Column) out of range for line \(position.line)",
        )
        let result = root.byteLength(upToUTF16: targetUTF16)
        precondition(
            root.newlines(beforeByte: result) == position.line,
            "byteOffset(of:) utf16Column \(position.utf16Column) exceeds the length of line \(position.line)",
        )
        return ByteOffset(result)
    }

    /// Converts a line/column position to the UTF-16 offset of the same
    /// position. Derived: composes `byteOffset(of: LinePosition)` and
    /// `utf16Offset(of: ByteOffset)`.
    ///
    /// - Precondition: same as `byteOffset(of: LinePosition)`.
    func utf16Offset(of position: LinePosition) -> UTF16Offset {
        let byte = byteOffset(of: position)
        let result = utf16Offset(of: byte)
        assert(
            linePosition(of: byte) == position,
            "utf16Offset(of:) round trip mismatch for \(position)",
        )
        return result
    }

    /// Converts a UTF-16 offset to its line/column position. Derived:
    /// composes `byteOffset(of: UTF16Offset)` and `linePosition(of: ByteOffset)`.
    ///
    /// - Precondition: same as `byteOffset(of: UTF16Offset)`.
    func linePosition(of offset: UTF16Offset) -> LinePosition {
        let byte = byteOffset(of: offset)
        let result = linePosition(of: byte)
        assert(
            utf16Offset(of: byte) == offset,
            "linePosition(of:) round trip mismatch for utf16Offset \(offset.value)",
        )
        return result
    }

    /// The byte range of line `line`'s content, excluding its trailing `\n`
    /// (the final line, which has no trailing `\n`, extends to `utf8Count`).
    ///
    /// - Precondition: `line` lies within `0..<lineCount`.
    func byteRange(ofLine line: Int) -> Range<ByteOffset> {
        precondition(
            (0 ..< lineCount).contains(line),
            "byteRange(ofLine:) line \(line) out of range 0..<\(lineCount)",
        )
        let start = root.byteOffsetOfLineStart(line)
        let end = line == lineCount - 1 ? utf8Count : root.byteOffsetOfLineStart(line + 1) - 1
        return ByteOffset(start) ..< ByteOffset(end)
    }
}
