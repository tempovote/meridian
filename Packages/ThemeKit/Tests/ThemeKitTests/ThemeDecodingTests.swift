import Foundation
import Testing
@testable import ThemeKit

@Suite("ThemeDecodingTests")
struct ThemeDecodingTests {
    @Test func decodesCompleteThemeJSON() throws {
        let json = """
        {
          "name": "Sample",
          "appearance": "light",
          "editor": {
            "background": "#FFFFFF", "caret": "#000000", "lineHighlight": "#EEEEEE", "bracketMatch": "#3E4451"
          },
          "tokens": {
            "keyword": { "color": "#AA00AA", "bold": true },
            "comment": { "color": "#888888", "italic": true },
            "plain": { "color": "#000000" }
          }
        }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.name == "Sample")
        #expect(theme.appearance == .light)
        #expect(theme.editor.background == "#FFFFFF")
        #expect(theme.editor.caret == "#000000")
        #expect(theme.editor.lineHighlight == "#EEEEEE")
        #expect(theme.editor.bracketMatch == "#3E4451")
        #expect(theme.tokens["keyword"]?.color == "#AA00AA")
        #expect(theme.tokens["keyword"]?.bold == true)
        #expect(theme.tokens["keyword"]?.italic == nil)
        #expect(theme.tokens["comment"]?.italic == true)
        #expect(theme.tokens["plain"]?.bold == nil)
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let original = Theme(
            name: "RoundTrip",
            appearance: .dark,
            editor: EditorColors(
                background: "#111111",
                caret: "#222222",
                lineHighlight: "#333333",
                bracketMatch: "#444444",
            ),
            tokens: ["keyword": TokenStyle(color: "#ABCDEF", bold: true, italic: false)],
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.appearance == original.appearance)
        #expect(decoded.editor.background == original.editor.background)
        #expect(decoded.editor.bracketMatch == original.editor.bracketMatch)
        #expect(decoded.tokens["keyword"]?.color == "#ABCDEF")
        #expect(decoded.tokens["keyword"]?.bold == true)
        #expect(decoded.tokens["keyword"]?.italic == false)
    }
}
