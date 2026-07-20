import Foundation
import SwiftTreeSitter
import TreeSitterJSON
import TreeSitterSwift

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
        let queryText: String

        switch languageID {
        case "json":
            guard let tsLanguage = tree_sitter_json() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
            queryText = HighlightQueries.json
        case "swift":
            guard let tsLanguage = tree_sitter_swift() else {
                throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
            }
            language = Language(tsLanguage)
            queryText = HighlightQueries.swift
        default:
            throw SyntaxKitError.grammarLoadFailed(languageID: languageID)
        }

        guard let queryData = queryText.data(using: .utf8) else {
            throw SyntaxKitError.queryCompilationFailed(
                languageID: languageID,
                underlying: SyntaxKitError.grammarLoadFailed(languageID: languageID),
            )
        }

        do {
            let query = try Query(language: language, data: queryData)
            return (language, query)
        } catch {
            throw SyntaxKitError.queryCompilationFailed(languageID: languageID, underlying: error)
        }
    }
}
