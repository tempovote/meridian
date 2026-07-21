import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceJavascriptGoldenTests")
struct SyntaxServiceJavascriptGoldenTests {
    @Test func javascriptFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        function greet() {
          return "hi";
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "javascript",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(10), type: .comment),
            TokenRun(range: ByteOffset(11) ..< ByteOffset(19), type: .keyword),
            TokenRun(range: ByteOffset(20) ..< ByteOffset(25), type: .variable),
            TokenRun(range: ByteOffset(20) ..< ByteOffset(25), type: .function),
            TokenRun(range: ByteOffset(25) ..< ByteOffset(26), type: .punctuation),
            TokenRun(range: ByteOffset(26) ..< ByteOffset(27), type: .punctuation),
            TokenRun(range: ByteOffset(28) ..< ByteOffset(29), type: .punctuation),
            TokenRun(range: ByteOffset(32) ..< ByteOffset(38), type: .keyword),
            TokenRun(range: ByteOffset(39) ..< ByteOffset(43), type: .string),
            TokenRun(range: ByteOffset(43) ..< ByteOffset(44), type: .punctuation),
            TokenRun(range: ByteOffset(45) ..< ByteOffset(46), type: .punctuation),
        ]
        #expect(runs == expected)
    }
}
