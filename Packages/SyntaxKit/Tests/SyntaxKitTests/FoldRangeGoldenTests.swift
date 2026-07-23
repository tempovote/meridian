import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("FoldRangeGoldenTests")
struct FoldRangeGoldenTests {
    private func folds(_ source: String, _ languageID: String) async throws -> [FoldRange] {
        let buffer = TextBuffer(source)
        let service = SyntaxService()
        return try await service.parse(
            documentID: DocumentID(),
            languageID: languageID,
            snapshot: buffer,
            version: buffer.version,
            edit: nil,
        ).folds
    }

    @Test func jsonObjectAndArrayFold() async throws {
        let source = """
        {
          "a": [
            1,
            2
          ],
          "b": true
        }
        """
        let result = try await folds(source, "json")
        // Byte offsets verified against the real capture output during
        // implementation (temporary print, then transcribed) — the shape
        // asserted here is the contract: outer object depth 1 spanning all
        // lines, inner array depth 2 spanning lines 1-4.
        #expect(result.count == 2)
        #expect(result[0].startLine == 0)
        #expect(result[0].endLine == 6)
        #expect(result[0].depth == 1)
        #expect(result[1].startLine == 1)
        #expect(result[1].endLine == 4)
        #expect(result[1].depth == 2)
    }

    @Test func swiftFunctionBodyFolds() async throws {
        let source = """
        func greet() {
            let x = 1
            print(x)
        }
        """
        let result = try await folds(source, "swift")
        #expect(result.count == 1)
        #expect(result[0].startLine == 0)
        #expect(result[0].endLine == 3)
        #expect(result[0].depth == 1)
    }

    @Test func pythonBlockFolds() async throws {
        let source = """
        def greet():
            x = 1
            print(x)
        """
        let result = try await folds(source, "python")
        #expect(result.count == 1)
        #expect(result[0].startLine == 0)
        #expect(result[0].endLine == 2)
        #expect(result[0].depth == 1)
    }

    @Test func singleLineRegionsAreDropped() async throws {
        let result = try await folds(#"{"a": 1}"#, "json")
        #expect(result.isEmpty)
    }

    @Test func languageWithoutFoldQueryReturnsEmpty() async throws {
        // Until Task 3 ships folds.scm for every grammar, any language
        // without one must degrade to "no folding", never throw.
        // (After Task 3, retarget this test at a hypothetical language by
        // deleting — no: keep it meaningful by asserting the API contract
        // through GrammarRegistry directly instead.)
        let registry = GrammarRegistry()
        _ = try await registry.grammar(for: "toml") // loads fine without folds.scm
        let foldQuery = try await registry.foldQuery(for: "toml")
        #expect(foldQuery == nil)
    }
}
