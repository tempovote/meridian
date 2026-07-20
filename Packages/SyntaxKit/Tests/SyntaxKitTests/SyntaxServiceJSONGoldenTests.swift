import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceJSONGoldenTests")
struct SyntaxServiceJSONGoldenTests {
    @Test func jsonFixtureProducesExpectedTokenRuns() async throws {
        let source = #"{"name": "value", "count": 42, "ok": true}"#
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "json",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (see Task 6 plan notes): captures sorted
        // less-specific-first by SwiftTreeSitter's `.highlights()`, so
        // @string appears before @string.special.key for the same range
        // where both match a pair's key node.
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(1) ..< ByteOffset(7), type: .string),
            TokenRun(range: ByteOffset(1) ..< ByteOffset(7), type: .string),
            TokenRun(range: ByteOffset(9) ..< ByteOffset(16), type: .string),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(25), type: .string),
            TokenRun(range: ByteOffset(18) ..< ByteOffset(25), type: .string),
            TokenRun(range: ByteOffset(27) ..< ByteOffset(29), type: .number),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(35), type: .string),
            TokenRun(range: ByteOffset(31) ..< ByteOffset(35), type: .string),
            TokenRun(range: ByteOffset(37) ..< ByteOffset(41), type: .constant),
        ]

        #expect(runs == expected)
    }
}
