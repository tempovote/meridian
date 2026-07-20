import DocumentCore
import SwiftTreeSitter
import Testing
@testable import SyntaxKit

@Suite("IncrementalParseEquivalenceTests")
struct IncrementalParseEquivalenceTests {
    @Test func incrementalReparseMatchesFromScratchParse() async throws {
        let originalSource = #"{"a": 1, "b": 2}"#
        var buffer = TextBuffer(originalSource)
        let oldBuffer = buffer

        // Edit: "1" -> "100" at byte offset 6 (the value of "a").
        let editRange = ByteOffset(6) ..< ByteOffset(7)
        let replacement = "100"
        let transaction = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: editRange, replacement: replacement)],
            origin: .user,
        )
        buffer.apply(transaction)
        let newBuffer = buffer

        #expect(newBuffer.string == #"{"a": 100, "b": 2}"#)

        let inputEdit = InputEdit(
            startByte: editRange.lowerBound.value,
            oldEndByte: editRange.upperBound.value,
            newEndByte: editRange.lowerBound.value + replacement.utf8.count,
            startPoint: treeSitterPoint(for: editRange.lowerBound, in: oldBuffer),
            oldEndPoint: treeSitterPoint(for: editRange.upperBound, in: oldBuffer),
            newEndPoint: treeSitterPoint(
                for: ByteOffset(editRange.lowerBound.value + replacement.utf8.count),
                in: newBuffer,
            ),
        )

        // Incremental path: same service/document, prior tree reused.
        let incrementalService = SyntaxService()
        let documentID = DocumentID()
        _ = try await incrementalService.reparse(
            documentID: documentID,
            languageID: "json",
            snapshot: oldBuffer,
            version: oldBuffer.version,
            edit: nil,
        )
        let incrementalRuns = try await incrementalService.reparse(
            documentID: documentID,
            languageID: "json",
            snapshot: newBuffer,
            version: newBuffer.version,
            edit: inputEdit,
        )

        // From-scratch path: fresh service/document, no prior tree.
        let freshService = SyntaxService()
        let freshRuns = try await freshService.reparse(
            documentID: DocumentID(),
            languageID: "json",
            snapshot: newBuffer,
            version: newBuffer.version,
            edit: nil,
        )

        #expect(incrementalRuns == freshRuns)
        #expect(!freshRuns.isEmpty)
    }
}
