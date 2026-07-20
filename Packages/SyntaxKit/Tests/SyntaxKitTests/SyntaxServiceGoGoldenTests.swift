import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceGoGoldenTests")
struct SyntaxServiceGoGoldenTests {
    @Test func goFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        func main() {
            x := 42
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "go",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(10), type: .comment),
            TokenRun(range: ByteOffset(11) ..< ByteOffset(15), type: .keyword),
            TokenRun(range: ByteOffset(16) ..< ByteOffset(20), type: .function),
            TokenRun(range: ByteOffset(16) ..< ByteOffset(20), type: .variable),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(30), type: .variable),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(33), type: .plain),
            TokenRun(range: ByteOffset(34) ..< ByteOffset(36), type: .number),
        ]
        #expect(runs == expected)
    }
}
