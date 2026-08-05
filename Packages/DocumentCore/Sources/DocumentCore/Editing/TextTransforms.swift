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
        let fullRange = prevLineStart ..< currentEnd

        let prevLineText = buffer.slice(prevLineStart ..< buffer.byteOffset(of: lineStartOffset(
            in: buffer,
            line: startLine,
        )))
        let currentLinesText = buffer
            .slice(buffer.byteOffset(of: lineStartOffset(in: buffer, line: startLine)) ..< currentEnd)

        let hadTrailingNewline = buffer.slice(fullRange).hasSuffix("\n")
        var rawBlock = currentLinesText + (currentLinesText.hasSuffix("\n") ? "" : "\n") + prevLineText
        if hadTrailingNewline, !rawBlock.hasSuffix("\n") {
            rawBlock.append("\n")
        } else if !hadTrailingNewline, rawBlock.hasSuffix("\n") {
            rawBlock.removeLast()
        }

        let edit = Edit(range: fullRange, replacement: rawBlock)
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
        let fullRange = currentStart ..< nextLineEnd

        let currentLinesEnd = buffer.byteOffset(of: lineStartOffset(in: buffer, line: endLine + 1))
        let currentLinesText = buffer.slice(currentStart ..< currentLinesEnd)
        let nextLineText = buffer.slice(currentLinesEnd ..< nextLineEnd)

        let hadTrailingNewline = buffer.slice(fullRange).hasSuffix("\n")
        var rawBlock = nextLineText + (nextLineText.hasSuffix("\n") ? "" : "\n") + currentLinesText
        if hadTrailingNewline, !rawBlock.hasSuffix("\n") {
            rawBlock.append("\n")
        } else if !hadTrailingNewline, rawBlock.hasSuffix("\n") {
            rawBlock.removeLast()
        }

        let edit = Edit(range: fullRange, replacement: rawBlock)
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
}

// MARK: - Line Operations & Helpers

public extension TextTransforms {
    static func convertLineEndings(in buffer: TextBuffer, to target: LineEnding) -> EditTransaction {
        let convertedText = buffer.convertingLineEndings(to: target).string
        if convertedText == buffer.string {
            return emptyTransaction(in: buffer)
        }

        let edit = Edit(range: ByteOffset(0) ..< ByteOffset(buffer.utf8Count), replacement: convertedText)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            origin: .user,
        )
    }

    /// Sorts lines covered by `selection` (or entire buffer if selection is empty/caret).
    static func sortLines(
        in buffer: TextBuffer,
        selection: SelectionSet = .empty,
        ascending: Bool = true,
        caseSensitive: Bool = true,
    ) -> EditTransaction {
        let (startByte, endByte) = coveredLineByteBounds(in: buffer, selection: selection)
        let blockText = buffer.slice(startByte ..< endByte)
        let hasTrailingNewline = blockText.hasSuffix("\n")
        var lines = blockText.components(separatedBy: "\n")
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        lines.sort { lineA, lineB in
            let cmp: ComparisonResult = if caseSensitive {
                lineA.compare(lineB)
            } else {
                lineA.caseInsensitiveCompare(lineB)
            }
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }

        var sortedText = lines.joined(separator: "\n")
        if hasTrailingNewline {
            sortedText.append("\n")
        }

        if sortedText == blockText {
            return emptyTransaction(in: buffer, selection: selection)
        }

        let edit = Edit(range: startByte ..< endByte, replacement: sortedText)
        let newEndByte = ByteOffset(startByte.value + sortedText.utf8.count)
        let selectionAfter = SelectionSet(ranges: [startByte ..< newEndByte])
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selectionAfter,
            origin: .user,
        )
    }

    /// Removes duplicate lines covered by `selection` (or entire buffer if selection is empty/caret), keeping first
    /// occurrence.
    static func deduplicateLines(
        in buffer: TextBuffer,
        selection: SelectionSet = .empty,
        caseSensitive: Bool = true,
    ) -> EditTransaction {
        let (startByte, endByte) = coveredLineByteBounds(in: buffer, selection: selection)
        let blockText = buffer.slice(startByte ..< endByte)
        let hasTrailingNewline = blockText.hasSuffix("\n")
        var lines = blockText.components(separatedBy: "\n")
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        var seen = Set<String>()
        var dedupedLines: [String] = []

        for line in lines {
            let key = caseSensitive ? line : line.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                dedupedLines.append(line)
            }
        }

        var dedupedText = dedupedLines.joined(separator: "\n")
        if hasTrailingNewline {
            dedupedText.append("\n")
        }

        if dedupedText == blockText {
            return emptyTransaction(in: buffer, selection: selection)
        }

        let edit = Edit(range: startByte ..< endByte, replacement: dedupedText)
        let newEndByte = ByteOffset(startByte.value + dedupedText.utf8.count)
        let selectionAfter = SelectionSet(ranges: [startByte ..< newEndByte])
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selectionAfter,
            origin: .user,
        )
    }

    /// Wraps the text in `selection` with `prefix`/`suffix` (e.g. Markdown
    /// bold/italic/strikethrough). With an empty selection, inserts the pair
    /// and places the caret between them so the user can type into it.
    static func wrapSelection(
        in buffer: TextBuffer,
        selection: SelectionSet,
        prefix: String,
        suffix: String,
    ) -> EditTransaction {
        let targetRange = selection.ranges.first ?? emptyCaretRange(in: buffer, selection: selection)
        let originalText = buffer.slice(targetRange)
        let replacement = prefix + originalText + suffix

        let edit = Edit(range: targetRange, replacement: replacement)
        let contentStart = ByteOffset(targetRange.lowerBound.value + prefix.utf8.count)
        let selectionAfter: SelectionSet = originalText.isEmpty
            ? SelectionSet(caretAt: contentStart)
            : SelectionSet(ranges: [contentStart ..< ByteOffset(contentStart.value + originalText.utf8.count)])

        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selectionAfter,
            origin: .user,
        )
    }

    /// Prefixes every line covered by `selection` with `prefix` (e.g.
    /// Markdown heading/list/ordered-list/blockquote markers).
    static func insertLinePrefix(in buffer: TextBuffer, selection: SelectionSet, prefix: String) -> EditTransaction {
        let (startByte, endByte) = coveredLineByteBounds(in: buffer, selection: selection)
        let blockText = buffer.slice(startByte ..< endByte)
        let hasTrailingNewline = blockText.hasSuffix("\n")
        var lines = blockText.components(separatedBy: "\n")
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        var prefixedText = lines.map { prefix + $0 }.joined(separator: "\n")
        if hasTrailingNewline {
            prefixedText.append("\n")
        }

        let edit = Edit(range: startByte ..< endByte, replacement: prefixedText)
        let newEndByte = ByteOffset(startByte.value + prefixedText.utf8.count)
        let selectionAfter = SelectionSet(ranges: [startByte ..< newEndByte])
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: selectionAfter,
            origin: .user,
        )
    }

    /// Wraps the selection as a Markdown link label (`[label](url)`),
    /// selecting the `url` placeholder so the user can type over it.
    static func insertMarkdownLink(in buffer: TextBuffer, selection: SelectionSet) -> EditTransaction {
        let targetRange = selection.ranges.first ?? emptyCaretRange(in: buffer, selection: selection)
        let label = buffer.slice(targetRange)
        let placeholder = "url"
        let replacement = "[\(label)](\(placeholder))"

        let edit = Edit(range: targetRange, replacement: replacement)
        let urlStart = ByteOffset(targetRange.lowerBound.value + 1 + label.utf8.count + 2)
        let urlEnd = ByteOffset(urlStart.value + placeholder.utf8.count)

        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: SelectionSet(ranges: [urlStart ..< urlEnd]),
            origin: .user,
        )
    }

    /// Wraps the selection as inline code (selection within one line) or a
    /// fenced code block (selection spanning multiple lines).
    static func insertMarkdownCode(in buffer: TextBuffer, selection: SelectionSet) -> EditTransaction {
        let targetRange = selection.ranges.first ?? emptyCaretRange(in: buffer, selection: selection)
        let startLine = buffer.linePosition(of: targetRange.lowerBound).line
        let endLine = buffer.linePosition(of: targetRange.upperBound).line
        return startLine == endLine
            ? wrapSelection(in: buffer, selection: selection, prefix: "`", suffix: "`")
            : wrapSelection(in: buffer, selection: selection, prefix: "```\n", suffix: "\n```")
    }

    /// Inserts a Markdown horizontal rule on its own new line, immediately
    /// after the line containing the end of `selection` (or the caret).
    static func insertMarkdownHorizontalRule(in buffer: TextBuffer, selection: SelectionSet) -> EditTransaction {
        insertStandaloneLine(in: buffer, selection: selection, text: "---")
    }

    /// Inserts a 2x2 Markdown table skeleton on its own new lines,
    /// immediately after the line containing the end of `selection` (or the
    /// caret).
    static func insertMarkdownTable(in buffer: TextBuffer, selection: SelectionSet) -> EditTransaction {
        insertStandaloneLine(
            in: buffer, selection: selection,
            text: "| Header | Header |\n| --- | --- |\n| Cell | Cell |",
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
            return (0, max(0, buffer.lineCount - 1))
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

    /// A zero-width range at the first selection range's start, or at the
    /// end of `buffer` if `selection` has no ranges at all.
    private static func emptyCaretRange(in buffer: TextBuffer, selection: SelectionSet) -> Range<ByteOffset> {
        let offset = selection.ranges.first?.lowerBound ?? ByteOffset(buffer.utf8Count)
        return offset ..< offset
    }

    /// Inserts `text` as its own new line immediately after the line
    /// containing the end of `selection` (or the caret if empty), leaving
    /// the caret at the end of the inserted line.
    private static func insertStandaloneLine(
        in buffer: TextBuffer,
        selection: SelectionSet,
        text: String,
    ) -> EditTransaction {
        let anchor = selection.ranges.first?.upperBound ?? ByteOffset(buffer.utf8Count)
        let line = buffer.linePosition(of: anchor).line
        let insertAt = buffer.byteRange(ofLine: line).upperBound
        let insertText = "\n" + text
        let edit = Edit(range: insertAt ..< insertAt, replacement: insertText)
        let caret = ByteOffset(insertAt.value + insertText.utf8.count)
        return EditTransaction(
            baseVersion: buffer.version,
            edits: [edit],
            selectionBefore: selection,
            selectionAfter: SelectionSet(caretAt: caret),
            origin: .user,
        )
    }
}
