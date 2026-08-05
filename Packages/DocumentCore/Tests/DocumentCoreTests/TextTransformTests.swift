import DocumentCore
import Testing

@Suite("TextTransformTests")
struct TextTransformTests {
    @Test func duplicateLines() {
        var buffer = TextBuffer("Line 1\nLine 2\nLine 3")
        let selection = SelectionSet(caretAt: ByteOffset(0))

        let tx = TextTransforms.duplicateLines(in: buffer, selection: selection)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\nLine 1\nLine 2\nLine 3")
    }

    @Test func moveLinesUpAndDown() {
        // Move Line 2 up
        var buffer1 = TextBuffer("Line 1\nLine 2\nLine 3")
        let sel1 = SelectionSet(caretAt: ByteOffset(7)) // on Line 2
        let txUp = TextTransforms.moveLinesUp(in: buffer1, selection: sel1)
        buffer1.apply(txUp)
        #expect(buffer1.string == "Line 2\nLine 1\nLine 3")

        // Move Line 2 down
        var buffer2 = TextBuffer("Line 1\nLine 2\nLine 3")
        let sel2 = SelectionSet(caretAt: ByteOffset(7)) // on Line 2
        let txDown = TextTransforms.moveLinesDown(in: buffer2, selection: sel2)
        buffer2.apply(txDown)
        #expect(buffer2.string == "Line 1\nLine 3\nLine 2")
    }

    @Test func deleteLines() {
        var buffer = TextBuffer("Line 1\nLine 2\nLine 3")
        let sel = SelectionSet(caretAt: ByteOffset(7)) // on Line 2

        let tx = TextTransforms.deleteLines(in: buffer, selection: sel)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\nLine 3")
    }

    @Test func trimTrailingWhitespace() {
        var buffer = TextBuffer("Hello   \nWorld\t\t\nClean")
        let tx = TextTransforms.trimTrailingWhitespace(in: buffer)
        buffer.apply(tx)

        #expect(buffer.string == "Hello\nWorld\nClean")
    }

    @Test func transformCase() {
        var buffer = TextBuffer("hello world")
        let txUpper = TextTransforms.transformCase(in: buffer) { $0.uppercased() }
        buffer.apply(txUpper)
        #expect(buffer.string == "HELLO WORLD")

        let txLower = TextTransforms.transformCase(in: buffer) { $0.lowercased() }
        buffer.apply(txLower)
        #expect(buffer.string == "hello world")
    }

    @Test func convertLineEndingsLFToCRLF() {
        var buffer = TextBuffer("Line 1\nLine 2\nLine 3")
        let tx = TextTransforms.convertLineEndings(in: buffer, to: .crlf)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\r\nLine 2\r\nLine 3")
    }

    @Test func convertLineEndingsCRLFToLF() {
        var buffer = TextBuffer("Line 1\r\nLine 2\r\nLine 3")
        let tx = TextTransforms.convertLineEndings(in: buffer, to: .lf)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\nLine 2\nLine 3")
    }

    @Test func convertLineEndingsMixedToLF() {
        var buffer = TextBuffer("Line 1\r\nLine 2\nLine 3\rLine 4")
        let tx = TextTransforms.convertLineEndings(in: buffer, to: .lf)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\nLine 2\nLine 3\nLine 4")
    }

    @Test func convertLineEndingsNoOpWhenAlreadyTarget() {
        var buffer = TextBuffer("Line 1\nLine 2")
        let tx = TextTransforms.convertLineEndings(in: buffer, to: .lf)
        buffer.apply(tx)

        #expect(buffer.string == "Line 1\nLine 2")
    }

    @Test func sortLinesAscendingAndDescending() {
        var buffer = TextBuffer("banana\napple\ncherry\n")
        let txAsc = TextTransforms.sortLines(in: buffer, ascending: true)
        buffer.apply(txAsc)
        #expect(buffer.string == "apple\nbanana\ncherry\n")

        let txDesc = TextTransforms.sortLines(in: buffer, ascending: false)
        buffer.apply(txDesc)
        #expect(buffer.string == "cherry\nbanana\napple\n")
    }

    @Test func deduplicateLinesPreservesFirstOccurrence() {
        var buffer = TextBuffer("apple\nbanana\napple\ncherry\nbanana\n")
        let tx = TextTransforms.deduplicateLines(in: buffer)
        buffer.apply(tx)
        #expect(buffer.string == "apple\nbanana\ncherry\n")
    }

    @Test func wrapSelectionWrapsSelectedText() {
        var buffer = TextBuffer("hello world")
        let selection = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(5)]) // "hello"
        let tx = TextTransforms.wrapSelection(in: buffer, selection: selection, prefix: "**", suffix: "**")
        buffer.apply(tx)
        #expect(buffer.string == "**hello** world")
    }

    @Test func wrapSelectionWithEmptySelectionInsertsAndPlacesCaretBetween() {
        var buffer = TextBuffer("")
        let selection = SelectionSet(caretAt: ByteOffset(0))
        let tx = TextTransforms.wrapSelection(in: buffer, selection: selection, prefix: "**", suffix: "**")
        buffer.apply(tx)
        #expect(buffer.string == "****")
        #expect(tx.selectionAfter == SelectionSet(caretAt: ByteOffset(2)))
    }

    @Test func insertLinePrefixPrefixesEachSelectedLine() {
        var buffer = TextBuffer("one\ntwo\nthree")
        let selection = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(7)]) // covers "one" and "two"
        let tx = TextTransforms.insertLinePrefix(in: buffer, selection: selection, prefix: "- ")
        buffer.apply(tx)
        #expect(buffer.string == "- one\n- two\nthree")
    }

    @Test func insertMarkdownLinkWrapsLabelAndSelectsURLPlaceholder() {
        var buffer = TextBuffer("click here")
        let selection = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(10)])
        let tx = TextTransforms.insertMarkdownLink(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "[click here](url)")
        #expect(tx.selectionAfter == SelectionSet(ranges: [ByteOffset(13) ..< ByteOffset(16)]))
    }

    @Test func insertMarkdownCodeUsesInlineBackticksForSingleLineSelection() {
        var buffer = TextBuffer("let x = 1")
        let selection = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(9)])
        let tx = TextTransforms.insertMarkdownCode(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "`let x = 1`")
    }

    @Test func insertMarkdownCodeUsesFencedBlockForMultiLineSelection() {
        var buffer = TextBuffer("let x = 1\nlet y = 2")
        let selection = SelectionSet(ranges: [ByteOffset(0) ..< ByteOffset(19)])
        let tx = TextTransforms.insertMarkdownCode(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "```\nlet x = 1\nlet y = 2\n```")
    }

    @Test func insertMarkdownHorizontalRuleInsertsNewLineBelowAnchorLine() {
        var buffer = TextBuffer("above\nbelow")
        let selection = SelectionSet(caretAt: ByteOffset(2)) // caret inside "above"
        let tx = TextTransforms.insertMarkdownHorizontalRule(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "above\n---\nbelow")
    }

    @Test func insertMarkdownHorizontalRuleOnLastLineWithNoTrailingNewline() {
        var buffer = TextBuffer("notes")
        let selection = SelectionSet(caretAt: ByteOffset(5))
        let tx = TextTransforms.insertMarkdownHorizontalRule(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "notes\n---")
    }

    @Test func insertMarkdownTableInsertsSkeletonBelowAnchorLine() {
        var buffer = TextBuffer("notes")
        let selection = SelectionSet(caretAt: ByteOffset(5))
        let tx = TextTransforms.insertMarkdownTable(in: buffer, selection: selection)
        buffer.apply(tx)
        #expect(buffer.string == "notes\n| Header | Header |\n| --- | --- |\n| Cell | Cell |")
    }
}
