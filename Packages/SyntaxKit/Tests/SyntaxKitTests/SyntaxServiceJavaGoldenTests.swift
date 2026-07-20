import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceJavaGoldenTests")
struct SyntaxServiceJavaGoldenTests {
    @Test func javaFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        class Main {
            int x = 42;
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "java",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(10), type: .comment),
            TokenRun(range: ByteOffset(11) ..< ByteOffset(16), type: .keyword),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(21), type: .variable),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(21), type: .type),
            TokenRun(range: ByteOffset(28) ..< ByteOffset(31), type: .type),
            TokenRun(range: ByteOffset(32) ..< ByteOffset(33), type: .variable),
            TokenRun(range: ByteOffset(36) ..< ByteOffset(38), type: .number),
        ]
        #expect(runs == expected)
    }
}
