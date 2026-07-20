import DocumentCore
import SwiftTreeSitter

/// Converts a `ByteOffset` to tree-sitter's `Point` (row + byte column
/// from line start — NOT the UTF-16 column `LinePosition` uses).
/// Recombines `TextBuffer`'s existing public coordinate conversions
/// rather than adding a new byte-column API to `DocumentCore`.
func treeSitterPoint(for byteOffset: ByteOffset, in buffer: TextBuffer) -> Point {
    let linePosition = buffer.linePosition(of: byteOffset)
    let lineStartByte = buffer.byteOffset(of: LinePosition(line: linePosition.line, utf16Column: 0))
    let byteColumn = byteOffset.value - lineStartByte.value
    return Point(row: linePosition.line, column: byteColumn)
}
