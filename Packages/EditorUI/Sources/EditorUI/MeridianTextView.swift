import AppKit

/// Custom `NSTextView` subclass for Meridian's editor view.
/// Overrides background drawing to render the current-line highlight
/// behind the active caret line.
@MainActor
public final class MeridianTextView: NSTextView {
    /// Whether the current line highlight background is drawn.
    public var isCurrentLineHighlightEnabled: Bool = true {
        didSet {
            if oldValue != isCurrentLineHighlightEnabled {
                needsDisplay = true
            }
        }
    }

    /// The color used for the current-line background highlight.
    public var currentLineHighlightColor: NSColor = .quaternaryLabelColor {
        didSet {
            needsDisplay = true
        }
    }

    /// Fired by `viewDidChangeEffectiveAppearance()` below — lets the
    /// owning `TextKit2Engine` react to a system light/dark toggle
    /// without `MeridianTextView` needing to know about `ThemeKit` itself.
    public var onEffectiveAppearanceChange: (() -> Void)?

    /// Fired when this text view becomes the window's first responder —
    /// lets the owning `TextKit2Engine`/host track focus across multiple
    /// panes sharing one document (split editor) without needing a
    /// custom `NSWindow` subclass to observe first-responder changes.
    public var onBecomeFirstResponder: (() -> Void)?

    /// Set by `TextKit2Engine`: returns true if the click point (in this
    /// view's local coordinates) hit a fold `…` placeholder and was
    /// handled (unfolded) — suppresses normal caret placement for that
    /// click.
    public var onFoldPlaceholderClick: ((NSPoint) -> Bool)?

    override public func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onBecomeFirstResponder?()
        }
        return result
    }

    override public func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onFoldPlaceholderClick?(point) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

    override public func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard isCurrentLineHighlightEnabled else { return }

        // Only highlight when selection is a caret (empty range), not a selection range.
        let selectedRanges = selectedRanges.map(\.rangeValue)
        guard selectedRanges.count == 1, selectedRanges[0].length == 0 else { return }

        let caretLocation = selectedRanges[0].location

        guard let textLayoutManager,
              let docStart = textLayoutManager.documentRange.location as NSTextLocation?,
              let location = textLayoutManager.location(docStart, offsetBy: caretLocation),
              let fragment = textLayoutManager.textLayoutFragment(for: location)
        else { return }

        let originY = fragment.layoutFragmentFrame.origin.y + textContainerOrigin.y
        let fragmentHeight = fragment.layoutFragmentFrame.height

        guard fragmentHeight > 0 else { return }

        let lineRect = NSRect(
            x: 0,
            y: originY,
            width: bounds.width,
            height: fragmentHeight,
        )

        guard lineRect.intersects(rect) else { return }

        NSGraphicsContext.saveGraphicsState()
        currentLineHighlightColor.setFill()
        lineRect.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
    }
}
