import Testing
@testable import SyntaxKit

@Suite("GrammarRegistryTests")
struct GrammarRegistryTests {
    @Test func loadsJSONGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "json")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func loadsSwiftGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "swift")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func unknownLanguageThrowsTypedError() async {
        let registry = GrammarRegistry()
        await #expect(throws: SyntaxKitError.self) {
            _ = try await registry.grammar(for: "cobol")
        }
    }

    @Test func cachesAcrossCalls() async throws {
        let registry = GrammarRegistry()
        let first = try await registry.grammar(for: "json")
        let second = try await registry.grammar(for: "json")
        #expect(first.language == second.language)
    }
}
