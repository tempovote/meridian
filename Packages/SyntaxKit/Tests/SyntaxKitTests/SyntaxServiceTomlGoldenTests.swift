import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceTomlGoldenTests")
struct SyntaxServiceTomlGoldenTests {
    @Test func tomlFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        # comment
        name = "value"
        count = 42
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "toml",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(9), type: .comment),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(14), type: .type),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(24), type: .property),
            TokenRun(range: ByteOffset(15) ..< ByteOffset(16), type: .plain),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(24), type: .string),
            TokenRun(range: ByteOffset(25) ..< ByteOffset(30), type: .type),
            TokenRun(range: ByteOffset(25) ..< ByteOffset(35), type: .property),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(32), type: .plain),
            TokenRun(range: ByteOffset(33) ..< ByteOffset(35), type: .number),
        ]
        #expect(runs == expected)
    }
}
