import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServicePythonGoldenTests")
struct SyntaxServicePythonGoldenTests {
    @Test func pythonFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        # comment
        def greet():
            return "hi"
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "python",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(9), type: .comment),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(13), type: .keyword),
            TokenRun(range: ByteOffset(14) ..< ByteOffset(19), type: .variable),
            TokenRun(range: ByteOffset(14) ..< ByteOffset(19), type: .function),
            TokenRun(range: ByteOffset(27) ..< ByteOffset(33), type: .keyword),
            TokenRun(range: ByteOffset(34) ..< ByteOffset(38), type: .string),
        ]
        #expect(runs == expected)
    }
}
