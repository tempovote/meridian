import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceMarkdownGoldenTests")
struct SyntaxServiceMarkdownGoldenTests {
    @Test func markdownFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        # Heading

        Some text.
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "markdown",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(1), type: .punctuation),
            TokenRun(range: ByteOffset(2) ..< ByteOffset(9), type: .plain),
        ]
        #expect(runs == expected)
    }
}
