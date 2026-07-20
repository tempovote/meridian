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

    /// Regression test for the bug where a second (or later) `reparse`
    /// call with `edit: nil` on a `documentID` that already had a cached
    /// tree would pass that stale, un-`.edit()`-ed tree to `parser.parse`
    /// as the incremental base — a misuse of tree-sitter's incremental
    /// API against genuinely different bytes, since `edit: nil` carries
    /// no information about what changed. `reparse` must instead treat
    /// `edit == nil` as "no edit info available" and force a full,
    /// from-scratch parse, discarding any cached tree for that call.
    ///
    /// This mirrors the real call pattern from `TextKit2Engine
    /// .highlightCurrentBuffer()`, which reparses the same `documentID`
    /// on every keystroke, always passing `edit: nil`.
    @Test func repeatedNilEditReparseMatchesFromScratchParse() async throws {
        let firstSource = #"{"name": "value", "count": 42, "ok": true}"#
        let secondSource = #"{"title": "other", "total": 7, "done": false}"#

        // Reuse-prone path: same service/documentID for both calls, both
        // with edit: nil. The second call must NOT reuse the first call's
        // tree as an incremental base.
        let reusedService = SyntaxService()
        let documentID = DocumentID()
        _ = try await reusedService.reparse(
            documentID: documentID,
            languageID: "json",
            snapshot: TextBuffer(firstSource),
            version: TextBuffer(firstSource).version,
            edit: nil,
        )
        let secondBuffer = TextBuffer(secondSource)
        let reusedRuns = try await reusedService.reparse(
            documentID: documentID,
            languageID: "json",
            snapshot: secondBuffer,
            version: secondBuffer.version,
            edit: nil,
        )

        // From-scratch path: fresh service/document parsing the second
        // buffer directly, with no prior tree to (mis)reuse.
        let freshService = SyntaxService()
        let freshRuns = try await freshService.reparse(
            documentID: DocumentID(),
            languageID: "json",
            snapshot: secondBuffer,
            version: secondBuffer.version,
            edit: nil,
        )

        #expect(reusedRuns == freshRuns)
        #expect(!freshRuns.isEmpty)
    }
}
