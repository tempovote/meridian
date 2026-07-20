import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServicePhpGoldenTests")
struct SyntaxServicePhpGoldenTests {
    @Test func phpFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        <?php
        // comment
        function greet() {
            return "hi";
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "php",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(5), type: .plain),
            TokenRun(range: ByteOffset(6) ..< ByteOffset(16), type: .comment),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(25), type: .keyword),
            TokenRun(range: ByteOffset(26) ..< ByteOffset(31), type: .function),
            TokenRun(range: ByteOffset(40) ..< ByteOffset(46), type: .keyword),
            TokenRun(range: ByteOffset(47) ..< ByteOffset(51), type: .string),
            TokenRun(range: ByteOffset(48) ..< ByteOffset(50), type: .string),
        ]
        #expect(runs == expected)
    }
}
