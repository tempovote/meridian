import AppKit

/// The 4 possible token-style font variants (regular/bold × non-italic/
/// italic) for a given family + size, resolved once (at init, or whenever
/// `TextKit2Engine.applyEditorSettings` rebuilds it on a settings change)
/// so `TextKit2Engine.applyHighlighting` stays a pure lookup with zero
/// style computation on the render path (ARCHITECTURE §13).
struct TokenFontCache {
    private let regular: NSFont
    private let bold: NSFont
    private let italic: NSFont
    private let boldItalic: NSFont

    /// If `familyName` isn't installed (a stale/hand-edited
    /// `settings.json` value), falls back to the system monospaced font —
    /// the same "tolerant of bad external edits" philosophy as
    /// `SettingsStore`'s decode-failure handling.
    init(familyName: String, size: CGFloat) {
        let regularFont = Self.resolvedFont(familyName: familyName, size: size, isBold: false)
        let boldFont = Self.resolvedFont(familyName: familyName, size: size, isBold: true)
        regular = regularFont
        bold = boldFont
        italic = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
        boldItalic = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
    }

    var baseFont: NSFont {
        regular
    }

    func font(bold: Bool, italic: Bool) -> NSFont {
        switch (bold, italic) {
        case (false, false): regular
        case (true, false): self.bold
        case (false, true): self.italic
        case (true, true): boldItalic
        }
    }

    private static func resolvedFont(familyName: String, size: CGFloat, isBold: Bool) -> NSFont {
        // NSFontManager's weight scale: 0 (ultralight) ... 5 (regular) ... 9 (bold) ... 15 (black).
        let weight = isBold ? 9 : 5
        if let font = NSFontManager.shared.font(
            withFamily: familyName,
            traits: isBold ? .boldFontMask : [],
            weight: weight,
            size: size,
        ) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: isBold ? .bold : .regular)
    }
}
