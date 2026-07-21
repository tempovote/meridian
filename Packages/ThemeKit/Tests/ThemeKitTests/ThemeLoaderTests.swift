import Foundation
import Testing
@testable import ThemeKit

@Suite("ThemeLoaderTests")
struct ThemeLoaderTests {
    @Test func loadingUnknownThemeNameThrowsResourceNotFound() {
        #expect(throws: ThemeKitError.self) {
            _ = try ThemeLoader.loadTheme(named: "does-not-exist")
        }
    }

    @Test func decodingMalformedJSONThrowsDecodingFailed() {
        let malformed = Data("{ not valid json".utf8)
        #expect(throws: ThemeKitError.self) {
            _ = try ThemeLoader.decodeTheme(from: malformed, name: "malformed")
        }
    }

    @Test func decodingValidJSONSucceeds() throws {
        let json = """
        {
          "name": "Test Theme",
          "appearance": "dark",
          "editor": { "background": "#111111", "caret": "#FFFFFF", "lineHighlight": "#222222" },
          "tokens": { "keyword": { "color": "#FF00FF", "bold": true } }
        }
        """
        let theme = try ThemeLoader.decodeTheme(from: Data(json.utf8), name: "test")
        #expect(theme.name == "Test Theme")
        #expect(theme.appearance == .dark)
        #expect(theme.tokens["keyword"]?.color == "#FF00FF")
    }

    @Test func loadingRealBundledResourceSucceeds() throws {
        let theme = try ThemeLoader.loadTheme(named: "meridian-dark")
        #expect(theme.name == "Meridian Dark")
    }
}
