import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceBashGoldenTests")
struct SyntaxServiceBashGoldenTests {
    @Test func bashFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        # comment
        echo "hi"
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "bash",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(9), type: .comment),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(14), type: .function),
            TokenRun(range: ByteOffset(15) ..< ByteOffset(19), type: .string),
        ]
        #expect(runs == expected)
    }
}
