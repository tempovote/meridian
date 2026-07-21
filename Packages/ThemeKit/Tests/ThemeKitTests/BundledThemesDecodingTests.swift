import Testing
@testable import ThemeKit

@Suite("BundledThemesDecodingTests")
struct BundledThemesDecodingTests {
    /// Mirrors SyntaxKit.TokenType.allCases' raw values without depending on
    /// SyntaxKit (ThemeKit stays dependency-free) — kept in sync manually;
    /// EditorUI's BundledThemeCoverageTests (Task 5) is the test that
    /// actually verifies this list against the real TokenType enum.
    private static let expectedTokenKeys: Set<String> = [
        "keyword", "string", "comment", "function", "type", "variable",
        "property", "number", "constant", "punctuation", "tag", "attribute", "plain",
    ]

    @Test func allFourBundledThemesDecodeWithCompleteTokenCoverage() {
        let themes = [
            BundledThemes.meridianDark,
            BundledThemes.meridianLight,
            BundledThemes.meridianDarkContrast,
            BundledThemes.meridianLightContrast,
        ]
        for theme in themes {
            #expect(
                Set(theme.tokens.keys) == Self.expectedTokenKeys,
                "\(theme.name) is missing or has extra token keys",
            )
        }
    }

    @Test func bundledThemeNamesAreUnique() {
        let names = [
            BundledThemes.meridianDark.name,
            BundledThemes.meridianLight.name,
            BundledThemes.meridianDarkContrast.name,
            BundledThemes.meridianLightContrast.name,
        ]
        #expect(Set(names).count == names.count)
    }

    @Test func darkThemesAreMarkedDarkAndLightThemesAreMarkedLight() {
        #expect(BundledThemes.meridianDark.appearance == .dark)
        #expect(BundledThemes.meridianDarkContrast.appearance == .dark)
        #expect(BundledThemes.meridianLight.appearance == .light)
        #expect(BundledThemes.meridianLightContrast.appearance == .light)
    }

    @Test func allFourBundledThemesHaveCompleteEditorColors() {
        let themes = [
            BundledThemes.meridianDark,
            BundledThemes.meridianLight,
            BundledThemes.meridianDarkContrast,
            BundledThemes.meridianLightContrast,
        ]
        for theme in themes {
            #expect(!theme.editor.background.isEmpty, "\(theme.name) has empty background")
            #expect(!theme.editor.caret.isEmpty, "\(theme.name) has empty caret")
            #expect(!theme.editor.lineHighlight.isEmpty, "\(theme.name) has empty lineHighlight")
            #expect(!theme.editor.bracketMatch.isEmpty, "\(theme.name) has empty bracketMatch")
        }
    }
}
