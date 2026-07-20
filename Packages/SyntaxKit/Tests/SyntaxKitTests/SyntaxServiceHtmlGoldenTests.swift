import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceHtmlGoldenTests")
struct SyntaxServiceHtmlGoldenTests {
    @Test func htmlFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        <!-- comment -->
        <div class="a">hi</div>
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "html",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(16), type: .comment),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(18), type: .punctuation),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(21), type: .plain),
            TokenRun(range: ByteOffset(22) ..< ByteOffset(27), type: .plain),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(30), type: .string),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(32), type: .punctuation),
            TokenRun(range: ByteOffset(34) ..< ByteOffset(36), type: .punctuation),
            TokenRun(range: ByteOffset(36) ..< ByteOffset(39), type: .plain),
            TokenRun(range: ByteOffset(39) ..< ByteOffset(40), type: .punctuation),
        ]
        #expect(runs == expected)
    }
}
