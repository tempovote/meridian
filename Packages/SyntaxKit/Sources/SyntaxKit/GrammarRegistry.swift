import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCpp
import TreeSitterCss
import TreeSitterGo
import TreeSitterHtml
import TreeSitterJava
import TreeSitterJavascript
import TreeSitterJSON
import TreeSitterPhp
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSwift
import TreeSitterToml
import TreeSitterTypescript
import TreeSitterYaml

/// Loads and caches (Language, Query) pairs by language identifier.
/// Independently testable/instantiable; owned by `SyntaxService` in
/// normal use.
public actor GrammarRegistry {
    private var cache: [String: (language: Language, query: Query)] = [:]

    public init() {}

    public func grammar(for languageID: String) throws -> (language: Language, query: Query) {
        if let cached = cache[languageID] {
            return cached
        }
        let loaded = try Self.loadGrammar(languageID: languageID)
        cache[languageID] = loaded
        return loaded
    }

    private static func loadGrammar(languageID: String) throws -> (language: Language, query: Query) {
        let language: Language

        switch languageID {
        case "json":
            guard let tsLanguage = tree_sitter_json() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "swift":
            guard let tsLanguage = tree_sitter_swift() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "javascript":
            guard let tsLanguage = tree_sitter_javascript() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "typescript":
            guard let tsLanguage = tree_sitter_typescript() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "html":
            guard let tsLanguage = tree_sitter_html() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "css":
            guard let tsLanguage = tree_sitter_css() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "python":
            guard let tsLanguage = tree_sitter_python() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "yaml":
            guard let tsLanguage = tree_sitter_yaml() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "toml":
            guard let tsLanguage = tree_sitter_toml() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "bash":
            guard let tsLanguage = tree_sitter_bash() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "c":
            guard let tsLanguage = tree_sitter_c() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "cpp":
            guard let tsLanguage = tree_sitter_cpp() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "rust":
            guard let tsLanguage = tree_sitter_rust() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "go":
            guard let tsLanguage = tree_sitter_go() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "java":
            guard let tsLanguage = tree_sitter_java() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "ruby":
            guard let tsLanguage = tree_sitter_ruby() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        case "php":
            guard let tsLanguage = tree_sitter_php() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
        default:
            throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
        }

        guard let queryURL = Bundle.module.url(
            forResource: "highlights",
            withExtension: "scm",
            subdirectory: "Resources/\(languageID)",
        ) else {
            throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
        }

        do {
            let queryData = try Data(contentsOf: queryURL)
            let query = try Query(language: language, data: queryData)
            return (language, query)
        } catch {
            throw SyntaxKitError.queryCompilationFailed(languageID: languageID, underlying: error)
        }
    }
}
