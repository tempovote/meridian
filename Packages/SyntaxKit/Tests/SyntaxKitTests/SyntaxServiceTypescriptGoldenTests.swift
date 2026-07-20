import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceTypescriptGoldenTests")
struct SyntaxServiceTypescriptGoldenTests {
    @Test func typescriptFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        function greet(): string {
          return "hi";
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "typescript",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(29) ..< ByteOffset(35), type: .type),
        ]
        #expect(runs == expected)
    }
}
