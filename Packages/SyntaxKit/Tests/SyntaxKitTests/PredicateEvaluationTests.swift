import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("PredicateEvaluationTests")
struct PredicateEvaluationTests {
    @Test func lowercaseReceiverNavigationIsNotCapturedAsType() async throws {
        let source = """
        func f() {
            myInstance.doThing()
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

        // "myInstance" starts at byte 15 and is 10 bytes long (15..<25):
        // "func f() {" is 10 bytes (0..<10), "\n" is byte 10, and the
        // 4-space indent is bytes 11..<15 — verified by counting
        // `Array(source.utf8)` directly, not by inspection.
        // With predicates evaluated (this task), #match? @type "^[A-Z]"
        // fails for "myInstance" (lowercase), so no .type capture exists
        // for that range. Without predicate evaluation (Phase 1's
        // behavior), this capture would incorrectly be present.
        let typeRunsOnReceiver = runs.filter { $0.type == .type && $0.range == ByteOffset(15) ..< ByteOffset(25) }
        #expect(typeRunsOnReceiver.isEmpty)
    }

    @Test func uppercaseReceiverNavigationIsCapturedAsType() async throws {
        let source = """
        func f() {
            MyType.method()
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

        // "MyType" starts at byte 15 and is 6 bytes long (15..<21) — same
        // byte accounting as the lowercase case above.
        // #match? @type "^[A-Z]" passes for "MyType", so this capture
        // exists whether or not predicates are evaluated — this test
        // proves predicate evaluation doesn't over-suppress valid matches.
        let typeRunsOnReceiver = runs.filter { $0.type == .type && $0.range == ByteOffset(15) ..< ByteOffset(21) }
        #expect(!typeRunsOnReceiver.isEmpty)
    }
}
