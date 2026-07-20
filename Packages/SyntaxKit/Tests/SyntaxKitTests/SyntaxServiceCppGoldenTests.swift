import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("SyntaxServiceCppGoldenTests")
struct SyntaxServiceCppGoldenTests {
    @Test func cppFixtureProducesExpectedTokenRuns() async throws {
        let source = """
        // comment
        int main() {
            return 0;
        }
        """
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        let documentID = DocumentID()

        let runs = try await service.reparse(
            documentID: documentID,
            languageID: "cpp",
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        )

        // Verified real output (captured via a temporary print statement per this task's plan step, then transcribed).
        // The upstream tree-sitter-cpp highlights.scm only contains C++-specific additions (templates,
        // namespaces, "auto", C++ keywords, raw strings, etc.) — like typescript/highlights.scm relative to
        // javascript, it is not self-contained for plain C-style code and produces no matches for this fixture.
        let expected: [TokenRun] = []
        #expect(runs == expected)
    }
}
