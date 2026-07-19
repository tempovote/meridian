import Foundation

/// Pure text and line transformation utilities operating over `TextBuffer`.
public enum TextTransforms {
    /// Duplicates the lines covered by `selection` directly below themselves.
    public static func duplicateLines(in buffer: TextBuffer, selection: SelectionSet = .empty) -> EditTransaction {
        let (startByte, endByte) = coveredLineByteBounds(in: buffer, selection: selection)
        let lineText = buffer.slice(startByte ..< endByte)
        let insertText = lineText.hasSuffix("\n") ? lineText : "\n" + lineText

        let edit = Edit(range: endByte ..< endByte, replacement: insertText)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: SelectionSet(caretAt: ByteOffset(endByte.value + insertText.utf8.count)),
            origin: .user,
        )
    }

    /// Moves the lines covered by `selection` up by one line.
    public static func moveLinesUp(in buffer: TextBuffer, selection: SelectionSet = .empty) -> EditTransaction {
        let (startLine, endLine) = coveredLineIndices(in: buffer, selection: selection)
        guard startLine > 0 else {
            return emptyTransaction(in: buffer, selection: selection)
        }

        let prevLineStart = buffer.byteOffset(of: lineStartOffset(in: buffer, line: startLine - 1))
        let currentEnd = lineEndByteOffset(in: buffer, line: endLine)

        let prevLineText = buffer.slice(prevLineStart ..< buffer.byteOffset(of: lineStartOffset(
            in: buffer,
            line: startLine,
        )))
        let currentLinesText = buffer
            .slice(buffer.byteOffset(of: lineStartOffset(in: buffer, line: startLine)) ..< currentEnd)

        let newBlock = currentLinesText + (currentLinesText.hasSuffix("\n") ? "" : "\n") + prevLineText
        let fullRange = prevLineStart ..< currentEnd

        let edit = Edit(range: fullRange, replacement: newBlock)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selection,
            origin: .user,
        )
    }

    /// Moves the lines covered by `selection` down by one line.
    public static func moveLinesDown(in buffer: TextBuffer, selection: SelectionSet = .empty) -> EditTransaction {
        let (startLine, endLine) = coveredLineIndices(in: buffer, selection: selection)
        guard endLine < buffer.lineCount - 1 else {
            return emptyTransaction(in: buffer, selection: selection)
        }

        let currentStart = buffer.byteOffset(of: lineStartOffset(in: buffer, line: startLine))
        let nextLineEnd = lineEndByteOffset(in: buffer, line: endLine + 1)

        let currentLinesEnd = buffer.byteOffset(of: lineStartOffset(in: buffer, line: endLine + 1))
        let currentLinesText = buffer.slice(currentStart ..< currentLinesEnd)
        let nextLineText = buffer.slice(currentLinesEnd ..< nextLineEnd)

        let newBlock = nextLineText + (nextLineText.hasSuffix("\n") ? "" : "\n") + currentLinesText
        let fullRange = currentStart ..< nextLineEnd

        let edit = Edit(range: fullRange, replacement: newBlock)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selection,
            origin: .user,
        )
    }

    /// Deletes the lines covered by `selection`.
    public static func deleteLines(in buffer: TextBuffer, selection: SelectionSet = .empty) -> EditTransaction {
        let (startByte, endByte) = coveredLineByteBounds(in: buffer, selection: selection)
        let edit = Edit(range: startByte ..< endByte, replacement: "")
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: SelectionSet(caretAt: startByte),
            origin: .user,
        )
    }

    /// Trims trailing spaces and tabs from all lines in `buffer`.
    public static func trimTrailingWhitespace(in buffer: TextBuffer) -> EditTransaction {
        let text = buffer.string
        let lines = text.components(separatedBy: "\n")
        let trimmedText = lines.map { line -> String in
            var trimmed = line
            while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") {
                trimmed.removeLast()
            }
            return trimmed
        }.joined(separator: "\n")

        if trimmedText == text {
            return emptyTransaction(in: buffer)
        }

        let edit = Edit(range: ByteOffset(0) ..< ByteOffset(buffer.utf8Count), replacement: trimmedText)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            origin: .user,
        )
    }

    /// Transforms the text in `selection` (or entire buffer if selection is empty) using `transform`.
    public static func transformCase(
        in buffer: TextBuffer,
        selection: SelectionSet = .empty,
        transform: (String) -> String,
    ) -> EditTransaction {
        let targetRange: Range<ByteOffset> = if selection.ranges.isEmpty || selection.ranges.first?.isEmpty == true {
            ByteOffset(0) ..< ByteOffset(buffer.utf8Count)
        } else {
            selection.ranges.first!
        }

        let originalText = buffer.slice(targetRange)
        let transformed = transform(originalText)

        if transformed == originalText {
            return emptyTransaction(in: buffer, selection: selection)
        }

        let edit = Edit(range: targetRange, replacement: transformed)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selection,
            origin: .user,
        )
    }

    // MARK: - Private Helpers

    private static func emptyTransaction(in buffer: TextBuffer, selection: SelectionSet = .empty) -> EditTransaction {
        EditTransaction(
            baseVersion: buffer.version,
            edits: [],
            selectionBefore: selection,
            selectionAfter: selection,
            origin: .user,
        )
    }

    private static func coveredLineIndices(in buffer: TextBuffer, selection: SelectionSet) -> (start: Int, end: Int) {
        guard let primary = selection.ranges.first else {
            return (0, 0)
        }
        let startLine = buffer.linePosition(of: primary.lowerBound).line
        let endLine = buffer.linePosition(of: primary.upperBound).line
        return (startLine, endLine)
    }

    private static func coveredLineByteBounds(
        in buffer: TextBuffer,
        selection: SelectionSet,
    ) -> (start: ByteOffset, end: ByteOffset) {
        let (startLine, endLine) = coveredLineIndices(in: buffer, selection: selection)
        let startByte = buffer.byteOffset(of: lineStartOffset(in: buffer, line: startLine))
        let endByte = lineEndByteOffset(in: buffer, line: endLine)
        return (startByte, endByte)
    }

    private static func lineStartOffset(in buffer: TextBuffer, line: Int) -> UTF16Offset {
        let lines = buffer.string.components(separatedBy: "\n")
        var utf16 = 0
        for index in 0 ..< min(line, lines.count) {
            utf16 += lines[index].utf16.count + 1
        }
        return UTF16Offset(utf16)
    }

    private static func lineEndByteOffset(in buffer: TextBuffer, line: Int) -> ByteOffset {
        let lines = buffer.string.components(separatedBy: "\n")
        if line >= lines.count - 1 {
            return ByteOffset(buffer.utf8Count)
        }
        var utf16 = 0
        for index in 0 ... line {
            utf16 += lines[index].utf16.count + 1
        }
        return buffer.byteOffset(of: UTF16Offset(utf16))
    }
}
