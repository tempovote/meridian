import Testing
@testable import ThemeKit

@MainActor
@Suite("ThemeEngineTests")
struct ThemeEngineTests {
    private func makeThemes() -> (dark: Theme, light: Theme) {
        let dark = Theme(
            name: "TestDark",
            appearance: .dark,
            editor: EditorColors(
                background: "#000000",
                caret: "#FFFFFF",
                lineHighlight: "#111111",
                bracketMatch: "#3E4451",
            ),
            tokens: [
                "keyword": TokenStyle(color: "#FF00FF", bold: true, italic: nil),
                "plain": TokenStyle(color: "#EEEEEE"),
            ],
        )
        let light = Theme(
            name: "TestLight",
            appearance: .light,
            editor: EditorColors(
                background: "#FFFFFF",
                caret: "#000000",
                lineHighlight: "#EEEEEE",
                bracketMatch: "#D6E4FF",
            ),
            tokens: [
                "keyword": TokenStyle(color: "#0000FF", bold: false, italic: true),
                "plain": TokenStyle(color: "#111111"),
            ],
        )
        return (dark, light)
    }

    @Test func initializesWithDarkThemeByDefault() {
        let (dark, light) = makeThemes()
        let engine = ThemeEngine(darkTheme: dark, lightTheme: light)
        #expect(engine.currentTheme.name == "TestDark")
        #expect(engine.resolvedStyle(for: "keyword").bold == true)
        #expect(engine.resolvedStyle(for: "keyword").italic == false)
    }

    @Test func appearanceDidChangeSwapsToLightTheme() {
        let (dark, light) = makeThemes()
        let engine = ThemeEngine(darkTheme: dark, lightTheme: light)
        engine.appearanceDidChange(isDark: false)
        #expect(engine.currentTheme.name == "TestLight")
        #expect(engine.resolvedStyle(for: "keyword").italic == true)
        #expect(engine.resolvedStyle(for: "keyword").bold == false)
    }

    @Test func appearanceDidChangeIsNoOpWhenAlreadyOnThatTheme() {
        let (dark, light) = makeThemes()
        let engine = ThemeEngine(darkTheme: dark, lightTheme: light)
        engine.appearanceDidChange(isDark: true) // already dark
        #expect(engine.currentTheme.name == "TestDark")
    }

    @Test func resolvedStyleFallsBackForUnknownTokenType() {
        let (dark, light) = makeThemes()
        let engine = ThemeEngine(darkTheme: dark, lightTheme: light)
        let style = engine.resolvedStyle(for: "nonexistentTokenType")
        #expect(style.color == .textColor)
        #expect(style.bold == false)
        #expect(style.italic == false)
    }

    @Test func editorColorsResolveFromCurrentThemeAndUpdateOnAppearanceChange() {
        let (dark, light) = makeThemes()
        let engine = ThemeEngine(darkTheme: dark, lightTheme: light)
        #expect(engine.editorColors.background == HexColor.nsColor(fromHex: "#000000"))
        #expect(engine.editorColors.bracketMatch == HexColor.nsColor(fromHex: "#3E4451"))
        engine.appearanceDidChange(isDark: false)
        #expect(engine.editorColors.background == HexColor.nsColor(fromHex: "#FFFFFF"))
        #expect(engine.editorColors.bracketMatch == HexColor.nsColor(fromHex: "#D6E4FF"))
    }
}
