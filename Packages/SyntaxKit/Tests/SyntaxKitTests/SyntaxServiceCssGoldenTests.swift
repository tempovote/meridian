import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceCssGoldenTests")
struct SyntaxServiceCssGoldenTests {
    @Test func cssFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        /* comment */
        .a { color: red; }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "css",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(13), type: .comment),
            TokenRun(range: ByteOffset(15) ..< ByteOffset(16), type: .property),
            TokenRun(range: ByteOffset(14) ..< ByteOffset(15), type: .punctuation),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(18), type: .punctuation),
            TokenRun(range: ByteOffset(19) ..< ByteOffset(24), type: .property),
            TokenRun(range: ByteOffset(24) ..< ByteOffset(25), type: .punctuation),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(30), type: .punctuation),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(32), type: .punctuation),
        ]
        #expect(runs == expected)
    }
}
