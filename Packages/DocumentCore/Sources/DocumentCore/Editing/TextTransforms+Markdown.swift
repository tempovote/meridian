import Foundation

// MARK: - Markdown Transforms

public extension TextTransforms {
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

    /// A zero-width range at the end of `buffer`.
    private static func emptyCaretRange(in buffer: TextBuffer, selection: SelectionSet) -> Range<ByteOffset> {
        let offset = ByteOffset(buffer.utf8Count)
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
