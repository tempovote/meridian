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

        // Verified real output: tree-sitter-swift's grammar splits a
        // string literal into separate opening-quote / content /
        // closing-quote nodes — three @string captures, not one.
        let expected: [TokenRun] = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(12), type: .comment),
            TokenRun(range: ByteOffset(13) ..< ByteOffset(17), type: .keyword),
            TokenRun(range: ByteOffset(29) ..< ByteOffset(35), type: .type),
            TokenRun(range: ByteOffset(42) ..< ByteOffset(45), type: .keyword),
            TokenRun(range: ByteOffset(53) ..< ByteOffset(54), type: .string),
            TokenRun(range: ByteOffset(54) ..< ByteOffset(59), type: .string),
            TokenRun(range: ByteOffset(59) ..< ByteOffset(60), type: .string),
            TokenRun(range: ByteOffset(65) ..< ByteOffset(71), type: .keyword),
        ]

        #expect(runs == expected)
    }
}
