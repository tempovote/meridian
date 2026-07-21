import AppKit

/// Computes the visual tab-stop width (`NSParagraphStyle` tab stops) for
/// a given font and character-count tab width. Controls only how wide a
/// literal `\t` renders — not what pressing Tab inserts (M5 Phase 1 scope,
/// see plan/spec Non-Goals).
enum TabStopStyle {
    static func paragraphStyle(tabWidth: Int, font: NSFont) -> NSParagraphStyle {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let interval = spaceWidth * CGFloat(max(tabWidth, 1))
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = interval
        style.tabStops = (1 ... 12).map { NSTextTab(textAlignment: .left, location: interval * CGFloat($0)) }
        return style
    }
}
