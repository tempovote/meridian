import SyntaxKit
import Testing
import ThemeKit
@testable import EditorUI

/// Lives in EditorUITests (not ThemeKitTests) because it's the first place
/// both SyntaxKit.TokenType and ThemeKit.Theme are visible together —
/// ThemeKit itself has no dependency on SyntaxKit (M4 Phase 3 design
/// decision 7). Fails loudly if a bundled theme is missing a style for
/// any real TokenType case (e.g. the .tag/.attribute cases Task 4 added).
@Suite("BundledThemeCoverageTests")
struct BundledThemeCoverageTests {
    @Test func everyBundledThemeDefinesEveryTokenType() {
        let themes = [
            BundledThemes.meridianDark,
            BundledThemes.meridianLight,
            BundledThemes.meridianDarkContrast,
            BundledThemes.meridianLightContrast,
        ]
        for theme in themes {
            for tokenType in TokenType.allCases {
                #expect(
                    theme.tokens[tokenType.rawValue] != nil,
                    "\(theme.name) has no explicit style for TokenType.\(tokenType.rawValue)",
                )
            }
        }
    }
}
