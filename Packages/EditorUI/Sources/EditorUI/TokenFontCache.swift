import AppKit

/// The 4 possible token-style font variants (regular/bold × non-italic/italic),
/// resolved once at init so `TextKit2Engine.applyHighlighting` stays a pure
/// lookup with zero style computation on the render path (ARCHITECTURE §13) —
/// in particular, `NSFontManager.convert`'s italic-trait conversion never runs
/// per run per repaint.
struct TokenFontCache {
    private let regular: NSFont
    private let bold: NSFont
    private let italic: NSFont
    private let boldItalic: NSFont

    init(baseSize: CGFloat) {
        let regularFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .bold)
        regular = regularFont
        bold = boldFont
        italic = NSFontManager.shared.convert(regularFont, toHaveTrait: .italicFontMask)
        boldItalic = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
    }

    func font(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
        switch (isBold, isItalic) {
        case (false, false): regular
        case (true, false): bold
        case (false, true): italic
        case (true, true): boldItalic
        }
    }
}
