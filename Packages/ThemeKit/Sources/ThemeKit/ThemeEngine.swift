import AppKit

/// Resolves a `Theme` (raw hex strings) into cached, render-ready
/// `NSColor` values — zero style computation on the render path
/// (ARCHITECTURE §13). Tracks a dark/light "Auto" pair and switches
/// between them when told the system appearance changed. Does not
/// observe `NSApp` itself — kept out of `ThemeEngine` so it stays
/// directly constructible/testable without a live `NSApplication`;
/// the `EditorUI`/App layer calls `appearanceDidChange(isDark:)`.
@MainActor
public final class ThemeEngine {
    private let darkTheme: Theme
    private let lightTheme: Theme
    public private(set) var currentTheme: Theme
    private var resolvedTokenStyles: [String: ResolvedStyle]
    public private(set) var editorColors: ResolvedEditorColors

    /// Returned for a token type with no matching entry in the current
    /// theme's `tokens` dict. Never observed for a bundled theme — see
    /// `BundledThemeCoverageTests` (Task 5) — but a defensive default.
    private static let fallbackStyle = ResolvedStyle(color: .textColor, bold: false, italic: false)

    public init(darkTheme: Theme, lightTheme: Theme) {
        self.darkTheme = darkTheme
        self.lightTheme = lightTheme
        currentTheme = darkTheme
        editorColors = Self.resolveEditorColors(darkTheme.editor)
        resolvedTokenStyles = Self.resolveTokenStyles(darkTheme.tokens)
    }

    public func resolvedStyle(for tokenTypeName: String) -> ResolvedStyle {
        resolvedTokenStyles[tokenTypeName] ?? Self.fallbackStyle
    }

    public func appearanceDidChange(isDark: Bool) {
        let newTheme = isDark ? darkTheme : lightTheme
        guard newTheme.name != currentTheme.name else { return }
        currentTheme = newTheme
        editorColors = Self.resolveEditorColors(newTheme.editor)
        resolvedTokenStyles = Self.resolveTokenStyles(newTheme.tokens)
    }

    private static func resolveTokenStyles(_ tokens: [String: TokenStyle]) -> [String: ResolvedStyle] {
        tokens.reduce(into: [:]) { result, entry in
            let (name, style) = entry
            let color = HexColor.nsColor(fromHex: style.color) ?? .textColor
            result[name] = ResolvedStyle(color: color, bold: style.bold ?? false, italic: style.italic ?? false)
        }
    }

    private static func resolveEditorColors(_ editor: EditorColors) -> ResolvedEditorColors {
        ResolvedEditorColors(
            background: HexColor.nsColor(fromHex: editor.background) ?? .textBackgroundColor,
            caret: HexColor.nsColor(fromHex: editor.caret) ?? .textColor,
            lineHighlight: HexColor.nsColor(fromHex: editor.lineHighlight) ?? .quaternaryLabelColor,
        )
    }
}
