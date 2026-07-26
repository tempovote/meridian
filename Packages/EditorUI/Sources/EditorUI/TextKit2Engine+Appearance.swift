import AppKit
import SettingsKit

extension TextKit2Engine {
    func applyEditorColors() {
        textView.backgroundColor = themeEngine.editorColors.background
        textView.insertionPointColor = themeEngine.editorColors.caret
        textView.currentLineHighlightColor = themeEngine.editorColors.lineHighlight
    }

    /// Rebuilds the font cache and tab-stop paragraph style from a new
    /// `EditorSettings` (either the Preferences UI wrote a change, or an
    /// external `settings.json` edit was live-reloaded), re-applies the
    /// paragraph style across the whole existing document immediately,
    /// and kicks off a repaint so every run picks up the new font.
    func applyEditorSettings(_ editor: EditorSettings) {
        fontCache = TokenFontCache(familyName: editor.fontFamily, size: CGFloat(editor.fontSize))
        paragraphStyle = TabStopStyle.paragraphStyle(tabWidth: editor.tabWidth, font: fontCache.baseFont)
        textView.font = fontCache.baseFont
        storage.addAttribute(
            .paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: storage.length),
        )
        highlightCurrentBuffer()
    }

    /// Called when `MeridianTextView.viewDidChangeEffectiveAppearance()`
    /// fires (system light/dark toggle, or a window moving to a screen
    /// with a different active appearance).
    func handleAppearanceChange() {
        let isDark = textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        themeEngine.appearanceDidChange(isDark: isDark)
        applyEditorColors()
        highlightCurrentBuffer()
    }
}
