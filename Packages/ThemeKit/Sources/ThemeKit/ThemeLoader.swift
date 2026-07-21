import Foundation

/// Loads and decodes a `.meridiantheme` resource via `Bundle.module`,
/// mirroring `SyntaxKit.GrammarRegistry.loadGrammar`'s
/// `Bundle.module.url(forResource:withExtension:subdirectory:)` pattern.
enum ThemeLoader {
    static func decodeTheme(from data: Data, name: String) throws -> Theme {
        do {
            return try JSONDecoder().decode(Theme.self, from: data)
        } catch {
            throw ThemeKitError.themeDecodingFailed(name: name, underlying: error)
        }
    }

    static func loadTheme(named name: String, bundle: Bundle = .module) throws -> Theme {
        guard let url = bundle.url(
            forResource: name,
            withExtension: "meridiantheme",
            subdirectory: "Resources",
        ) else {
            throw ThemeKitError.themeResourceNotFound(name: name)
        }
        let data = try Data(contentsOf: url)
        return try decodeTheme(from: data, name: name)
    }
}
