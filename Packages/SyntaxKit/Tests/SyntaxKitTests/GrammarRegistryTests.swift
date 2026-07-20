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

    @Test func loadsJavascriptGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "javascript")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func loadsPythonGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "python")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func loadsRustGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "rust")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func loadsRubyGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "ruby")
        #expect(language.symbolCount > 0)
        #expect(query.patternCount > 0)
    }

    @Test func loadsMarkdownGrammar() async throws {
        let registry = GrammarRegistry()
        let (language, query) = try await registry.grammar(for: "markdown")
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
