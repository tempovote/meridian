import Foundation

/// Whether a theme is intended for light or dark system appearance.
public enum ThemeAppearance: String, Codable, Sendable, Equatable {
    case light
    case dark
}

/// Base editor chrome colors a theme provides, as hex strings (e.g. "#1E2127").
public struct EditorColors: Codable, Sendable {
    public let background: String
    public let caret: String
    public let lineHighlight: String

    public init(background: String, caret: String, lineHighlight: String) {
        self.background = background
        self.caret = caret
        self.lineHighlight = lineHighlight
    }
}

/// Styling for one semantic token type, as defined in a theme's `tokens` map.
public struct TokenStyle: Codable, Sendable {
    public let color: String
    public let bold: Bool?
    public let italic: Bool?

    public init(color: String, bold: Bool? = nil, italic: Bool? = nil) {
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

/// A complete `.meridiantheme` theme: editor chrome colors plus a color/style
/// for every semantic token type `SyntaxKit` produces. `tokens` is keyed by
/// `SyntaxKit.TokenType.rawValue` (e.g. `"keyword"`, `"string"`) — `ThemeKit`
/// itself has no dependency on `SyntaxKit`; the string keys are the contract
/// (see `EditorUI.TextKit2Engine`, the layer that bridges the two).
public struct Theme: Codable, Sendable {
    public let name: String
    public let appearance: ThemeAppearance
    public let editor: EditorColors
    public let tokens: [String: TokenStyle]

    public init(name: String, appearance: ThemeAppearance, editor: EditorColors, tokens: [String: TokenStyle]) {
        self.name = name
        self.appearance = appearance
        self.editor = editor
        self.tokens = tokens
    }
}
