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
import TreeSitterMarkdown
import TreeSitterPhp
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSwift
import TreeSitterToml
import TreeSitterTypescript
import TreeSitterXml
import TreeSitterYaml

/// Loads and caches (Language, Query) pairs by language identifier.
/// Independently testable/instantiable; owned by `SyntaxService` in
/// normal use.
public actor GrammarRegistry {
    private var cache: [String: (language: Language, query: Query)] = [:]
    private var foldCache: [String: Query?] = [:]

    public init() {}

    public func grammar(for languageID: String) throws -> (language: Language, query: Query) {
        if let cached = cache[languageID] {
            return cached
        }
        let loaded = try Self.loadGrammar(languageID: languageID)
        cache[languageID] = loaded
        return loaded
    }

    /// The compiled `folds.scm` query for `languageID`, or nil when the
    /// grammar bundles no fold query (that language has no folding).
    /// A malformed bundled query is a programmer error and throws.
    public func foldQuery(for languageID: String) throws -> Query? {
        // Subscript lookup on [String: Query?] yields Query?? — a cached
        // "no fold query" (nil inner value) still hits this branch and is
        // returned correctly.
        if let cached = foldCache[languageID] {
            return cached
        }
        let (language, _) = try grammar(for: languageID)
        guard let queryURL = Bundle.module.url(
            forResource: "folds",
            withExtension: "scm",
            subdirectory: "Resources/\(languageID)",
        ) else {
            // `foldCache[languageID] = nil` would REMOVE the key (the
            // classic optional-of-optional dictionary trap) — updateValue
            // stores an actual nil value so the bundle-miss is cached.
            foldCache.updateValue(nil, forKey: languageID)
            return nil
        }
        do {
            let queryData = try Data(contentsOf: queryURL)
            let query = try Query(language: language, data: queryData)
            foldCache[languageID] = query
            return query
        } catch {
            throw SyntaxKitError.queryCompilationFailed(languageID: languageID, underlying: error)
        }
    }

    /// Maps a `languageID` to its vendored grammar's C entry point. Add one
    /// entry here (and a matching `import TreeSitter<Lang>` above) to wire
    /// up a new grammar — no `switch` case needed.
    private static let languageLoaders: [String: @Sendable () -> OpaquePointer?] = [
        "json": tree_sitter_json,
        "swift": tree_sitter_swift,
        "javascript": tree_sitter_javascript,
        "typescript": tree_sitter_typescript,
        "html": tree_sitter_html,
        "css": tree_sitter_css,
        "python": tree_sitter_python,
        "yaml": tree_sitter_yaml,
        "toml": tree_sitter_toml,
        "bash": tree_sitter_bash,
        "c": tree_sitter_c,
        "cpp": tree_sitter_cpp,
        "rust": tree_sitter_rust,
        "go": tree_sitter_go,
        "java": tree_sitter_java,
        "ruby": tree_sitter_ruby,
        "php": tree_sitter_php,
        "markdown": tree_sitter_markdown,
        "xml": tree_sitter_xml,
    ]

    private static func loadGrammar(languageID: String) throws -> (language: Language, query: Query) {
        guard let loadTSLanguage = languageLoaders[languageID], let tsLanguage = loadTSLanguage() else {
            throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
        }
        let language = Language(tsLanguage)

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
