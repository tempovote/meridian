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
}
