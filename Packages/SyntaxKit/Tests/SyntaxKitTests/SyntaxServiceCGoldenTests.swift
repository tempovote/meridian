import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceCGoldenTests")
struct SyntaxServiceCGoldenTests {
    @Test func cFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        int main() {
            return 0;
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "c",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(10), type: .comment),
            TokenRun(range: ByteOffset(11) ..< ByteOffset(14), type: .type),
            TokenRun(range: ByteOffset(15) ..< ByteOffset(19), type: .variable),
            TokenRun(range: ByteOffset(15) ..< ByteOffset(19), type: .function),
            TokenRun(range: ByteOffset(28) ..< ByteOffset(34), type: .keyword),
            TokenRun(range: ByteOffset(35) ..< ByteOffset(36), type: .number),
            TokenRun(range: ByteOffset(36) ..< ByteOffset(37), type: .plain),
        ]
        #expect(runs == expected)
    }
}
