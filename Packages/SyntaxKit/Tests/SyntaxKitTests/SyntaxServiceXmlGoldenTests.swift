import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceXmlGoldenTests")
struct SyntaxServiceXmlGoldenTests {
    @Test func xmlFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        <!-- comment -->
        <root attr="value">text</root>
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "xml",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        // Only the 2 tag-name entries (.plain -> .tag) change vs. the M4
        // Phase 2 version of this test — see TokenType.swift for why. The
        // "attr" entry stays .property: xml's grammar captures ordinary
        // element attribute names as (Attribute (Name) @property), not
        // @attribute (that capture is reserved for DTD keywords like
        // #REQUIRED, absent from this fixture) — confirmed by reading
        // Resources/xml/highlights.scm, not assumed.
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(16), type: .comment),
            TokenRun(range: ByteOffset(17) ..< ByteOffset(18), type: .punctuation),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(22), type: .tag),
            TokenRun(range: ByteOffset(23) ..< ByteOffset(27), type: .property),
            TokenRun(range: ByteOffset(27) ..< ByteOffset(28), type: .plain),
            TokenRun(range: ByteOffset(28) ..< ByteOffset(35), type: .string),
            TokenRun(range: ByteOffset(28) ..< ByteOffset(29), type: .punctuation),
            TokenRun(range: ByteOffset(35) ..< ByteOffset(36), type: .punctuation),
            TokenRun(range: ByteOffset(34) ..< ByteOffset(35), type: .punctuation),
            TokenRun(range: ByteOffset(36) ..< ByteOffset(40), type: .plain),
            TokenRun(range: ByteOffset(40) ..< ByteOffset(42), type: .punctuation),
            TokenRun(range: ByteOffset(42) ..< ByteOffset(46), type: .tag),
            TokenRun(range: ByteOffset(46) ..< ByteOffset(47), type: .punctuation),
        ]
        #expect(runs == expected)
    }
}
