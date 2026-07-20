import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceSwiftGoldenTests")
struct SyntaxServiceSwiftGoldenTests {
    @Test func swiftFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // A comment
        func greet() -> String {
            let name = "world"
            return name
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "swift",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (real upstream query + predicates evaluated,
        // computed during planning against this exact fixture). Two real,
        // non-obvious things this captures:
        // 1. `(comment) @comment @spell` puts TWO captures on the same
        //    byte range (0..<12) — one @comment, one @spell. TokenType's
        //    normalization has no case for "spell" and it has no dots to
        //    strip, so it falls through to .plain. This is real, intended
        //    behavior of the unmodified upstream query, not a bug to fix.
        // 2. "->" (the arrow) and "=" are captured as bare @operator,
        //    which also has no TokenType case and normalizes to .plain.
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(12), type: .comment),
            TokenRun(range: ByteOffset(0) ..< ByteOffset(12), type: .plain),
            TokenRun(range: ByteOffset(13) ..< ByteOffset(17), type: .keyword),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(23), type: .plain),
            TokenRun(range: ByteOffset(23) ..< ByteOffset(24), type: .punctuation),
            TokenRun(range: ByteOffset(24) ..< ByteOffset(25), type: .punctuation),
            TokenRun(range: ByteOffset(26) ..< ByteOffset(28), type: .plain),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(35), type: .type),
            TokenRun(range: ByteOffset(36) ..< ByteOffset(37), type: .punctuation),
            TokenRun(range: ByteOffset(42) ..< ByteOffset(45), type: .keyword),
            TokenRun(range: ByteOffset(46) ..< ByteOffset(50), type: .variable),
            TokenRun(range: ByteOffset(51) ..< ByteOffset(52), type: .plain),
            TokenRun(range: ByteOffset(53) ..< ByteOffset(54), type: .string),
            TokenRun(range: ByteOffset(54) ..< ByteOffset(59), type: .string),
            TokenRun(range: ByteOffset(59) ..< ByteOffset(60), type: .string),
            TokenRun(range: ByteOffset(65) ..< ByteOffset(71), type: .keyword),
            TokenRun(range: ByteOffset(77) ..< ByteOffset(78), type: .punctuation),
        ]

        #expect(runs == expected)
    }
}
