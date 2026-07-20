import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceYamlGoldenTests")
struct SyntaxServiceYamlGoldenTests {
    @Test func yamlFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        # comment
        name: value
        count: 42
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "yaml",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(9), type: .comment),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(14), type: .string),
            TokenRun(range: ByteOffset(10) ..< ByteOffset(14), type: .property),
            TokenRun(range: ByteOffset(14) ..< ByteOffset(15), type: .punctuation),
            TokenRun(range: ByteOffset(16) ..< ByteOffset(21), type: .string),
            TokenRun(range: ByteOffset(22) ..< ByteOffset(27), type: .string),
            TokenRun(range: ByteOffset(22) ..< ByteOffset(27), type: .property),
            TokenRun(range: ByteOffset(27) ..< ByteOffset(28), type: .punctuation),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(31), type: .number),
        ]
        #expect(runs == expected)
    }
}
