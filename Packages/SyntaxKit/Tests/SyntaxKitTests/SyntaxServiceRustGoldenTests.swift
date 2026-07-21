import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceRustGoldenTests")
struct SyntaxServiceRustGoldenTests {
    @Test func rustFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        fn main() {
            let x = 42;
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "rust",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(10), type: .comment),
            TokenRun(range: ByteOffset(11) ..< ByteOffset(13), type: .keyword),
            TokenRun(range: ByteOffset(14) ..< ByteOffset(18), type: .function),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(19), type: .punctuation),
            TokenRun(range: ByteOffset(19) ..< ByteOffset(20), type: .punctuation),
            TokenRun(range: ByteOffset(21) ..< ByteOffset(22), type: .punctuation),
            TokenRun(range: ByteOffset(27) ..< ByteOffset(30), type: .keyword),
            TokenRun(range: ByteOffset(35) ..< ByteOffset(37), type: .constant),
            TokenRun(range: ByteOffset(37) ..< ByteOffset(38), type: .punctuation),
            TokenRun(range: ByteOffset(39) ..< ByteOffset(40), type: .punctuation),
        ]
        #expect(runs == expected)
    }
}
