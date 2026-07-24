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

    /// Whether indentation guides are drawn.
    public var isIndentGuidesEnabled: Bool = true {
        didSet {
            if oldValue != isIndentGuidesEnabled {
                needsDisplay = true
            }
        }
    }

    /// Tab width in spaces used to compute indentation guide columns.
    public var tabWidth: Int = 4 {
        didSet {
            if oldValue != tabWidth {
                needsDisplay = true
            }
        }
    }

    /// Color used for inactive indentation guide lines.
    public var indentGuideColor: NSColor = .separatorColor.withAlphaComponent(0.3) {
        didSet { needsDisplay = true }
    }

    /// Color used for active indentation guide line at caret.
    public var activeIndentGuideColor: NSColor = .secondaryLabelColor.withAlphaComponent(0.6) {
        didSet { needsDisplay = true }
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

    /// Set by `TextKit2Engine`: handles Option-click to toggle carets at the clicked point.
    public var onOptionClick: ((NSPoint) -> Void)?

    private var customSelectedRanges: [NSValue]?

    override public var selectedRanges: [NSValue] {
        get {
            if let customSelectedRanges {
                return customSelectedRanges
            }
            return super.selectedRanges
        }
        set {
            if newValue.count > 1 {
                customSelectedRanges = newValue
            } else {
                customSelectedRanges = nil
            }
            super.selectedRanges = newValue
        }
    }

    override public func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        if ranges.count > 1 {
            customSelectedRanges = ranges
        } else {
            customSelectedRanges = nil
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    override public func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onBecomeFirstResponder?()
        }
        return result
    }

    override public func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        print("[MultiCaret Debug] MeridianTextView.keyDown: keyCode=\(event.keyCode), flags=\(flags)")
        if flags == [.option, .command] {
            if event.keyCode == 126 { // Up arrow
                print("[MultiCaret Debug] Triggering addCaretAbove:")
                NSApp.sendAction(Selector(("addCaretAbove:")), to: nil, from: self)
                return
            } else if event.keyCode == 125 { // Down arrow
                print("[MultiCaret Debug] Triggering addCaretBelow:")
                NSApp.sendAction(Selector(("addCaretBelow:")), to: nil, from: self)
                return
            }
        }
        super.keyDown(with: event)
    }

    /// Set by `TextKit2Engine`: handles Option+Cmd+Up action.
    public var onAddCaretAbove: (() -> Void)?
    /// Set by `TextKit2Engine`: handles Option+Cmd+Down action.
    public var onAddCaretBelow: (() -> Void)?

    @objc public func addCaretAbove(_ sender: Any?) {
        print("[MultiCaret Debug] MeridianTextView.addCaretAbove action invoked")
        onAddCaretAbove?()
    }

    @objc public func addCaretBelow(_ sender: Any?) {
        print("[MultiCaret Debug] MeridianTextView.addCaretBelow action invoked")
        onAddCaretBelow?()
    }

    override public func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        print("[MultiCaret Debug] MeridianTextView.mouseDown: point=\(point), flags=\(flags), hasOptionClick=\(onOptionClick != nil)")
        if onFoldPlaceholderClick?(point) == true {
            print("[MultiCaret Debug] Handled by fold placeholder click")
            return
        }
        if flags.contains(.option) || flags.contains(.command) {
            if window?.firstResponder != self {
                print("[MultiCaret Debug] Making MeridianTextView first responder")
                window?.makeFirstResponder(self)
            }
            if let onOptionClick {
                print("[MultiCaret Debug] Invoking onOptionClick(at: \(point))")
                onOptionClick(point)
            } else {
                print("[MultiCaret Debug] WARNING: onOptionClick is nil!")
            }
            return
        }
        super.mouseDown(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        print("[MultiCaret Debug] MeridianTextView.mouseUp: flags=\(flags), customSelectedRangesCount=\(customSelectedRanges?.count ?? 0)")
        if flags.contains(.option) || flags.contains(.command) || (customSelectedRanges?.count ?? 0) > 1 {
            print("[MultiCaret Debug] Suppressing super.mouseUp for multi-caret selection")
            return
        }
        super.mouseUp(with: event)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

    override public func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        drawCurrentLineHighlights(in: rect)
        drawIndentGuides(in: rect)
    }

    override public func draw(_ rect: NSRect) {
        super.draw(rect)
        drawCarets(in: rect)
    }

    private func drawCarets(in rect: NSRect) {
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 {
            print("[MultiCaret Debug] MeridianTextView.drawCarets: selectedRanges.count=\(ranges.count), ranges=\(ranges)")
        }
        guard ranges.count > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        let caretColor = insertionPointColor ?? NSColor.controlAccentColor
        caretColor.setFill()

        var drawnCount = 0
        for selected in ranges where selected.length == 0 {
            guard let caretRect = caretRect(for: selected) else {
                print("[MultiCaret Debug] Could not compute caretRect for selected range: \(selected)")
                continue
            }
            print("[MultiCaret Debug] Caret rect for range \(selected): \(caretRect)")
            if caretRect.intersects(rect) {
                caretRect.fill()
                drawnCount += 1
            }
        }
        print("[MultiCaret Debug] drawCarets finished drawing \(drawnCount) carets")
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCurrentLineHighlights(in rect: NSRect) {
        guard isCurrentLineHighlightEnabled else { return }

        let ranges = selectedRanges.map(\.rangeValue)
        guard !ranges.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        currentLineHighlightColor.setFill()

        for selected in ranges where selected.length == 0 {
            guard let lineRect = lineHighlightRect(for: selected) else { continue }
            if lineRect.intersects(rect) {
                lineRect.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func caretRect(for characterRange: NSRange) -> NSRect? {
        guard let textLayoutManager,
              let docStart = textLayoutManager.documentRange.location as NSTextLocation?,
              let caretLoc = textLayoutManager.location(docStart, offsetBy: characterRange.location),
              let fragment = textLayoutManager.textLayoutFragment(for: caretLoc)
        else { return nil }

        let frame = fragment.layoutFragmentFrame
        let originY = frame.origin.y + textContainerOrigin.y
        let height = frame.height > 0 ? frame.height : (font?.pointSize ?? 13) * 1.2

        var originX = textContainerOrigin.x + frame.origin.x
        let charOffsetInElement = textLayoutManager.offset(from: fragment.rangeInElement.location, to: caretLoc)

        for lineFragment in fragment.textLineFragments {
            let lineRange = lineFragment.characterRange
            if charOffsetInElement >= lineRange.location && charOffsetInElement <= (lineRange.location + lineRange.length) {
                let indexInLine = charOffsetInElement - lineRange.location
                let locInLine = lineFragment.locationForCharacter(at: indexInLine)
                originX += locInLine.x
                break
            }
        }

        return NSRect(x: originX, y: originY, width: 2.0, height: height)
    }

    private func lineHighlightRect(for characterRange: NSRange) -> NSRect? {
        guard let textLayoutManager,
              let docStart = textLayoutManager.documentRange.location as NSTextLocation?,
              let caretLoc = textLayoutManager.location(docStart, offsetBy: characterRange.location),
              let fragment = textLayoutManager.textLayoutFragment(for: caretLoc)
        else { return nil }

        let frame = fragment.layoutFragmentFrame
        let originY = frame.origin.y + textContainerOrigin.y
        let height = frame.height > 0 ? frame.height : (font?.pointSize ?? 13) * 1.2

        return NSRect(x: 0, y: originY, width: bounds.width, height: height)
    }

    private func drawIndentGuides(in rect: NSRect) {
        guard isIndentGuidesEnabled, tabWidth > 0, let font else { return }
        guard let textLayoutManager else { return }

        let spaceAdvance = " ".size(withAttributes: [.font: font]).width
        guard spaceAdvance > 0 else { return }
        let indentStepWidth = spaceAdvance * CGFloat(tabWidth)

        let selectedLocation = selectedRanges.first?.rangeValue.location ?? 0
        var activeIndentLevel = -1

        if let docStart = textLayoutManager.documentRange.location as NSTextLocation?,
           let caretLoc = textLayoutManager.location(docStart, offsetBy: selectedLocation),
           let caretFragment = textLayoutManager.textLayoutFragment(for: caretLoc),
           let paragraph = caretFragment.textElement as? NSTextParagraph
        {
            let caretLineText = paragraph.attributedString.string
            activeIndentLevel = computeIndentLevel(for: caretLineText)
        }

        NSGraphicsContext.saveGraphicsState()
        guard let docStart = textLayoutManager.documentRange.location as NSTextLocation? else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        textLayoutManager.enumerateTextLayoutFragments(from: docStart, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let originY = frame.origin.y + textContainerOrigin.y
            let lineRect = NSRect(x: 0, y: originY, width: bounds.width, height: frame.height)
            guard lineRect.intersects(rect) else { return true }

            let lineText = (fragment.textElement as? NSTextParagraph)?.attributedString.string ?? ""
            let indentLevel = computeIndentLevel(for: lineText)
            if indentLevel <= 0 {
                return true
            }

            for level in 1 ... indentLevel {
                let x = textContainerOrigin.x + CGFloat(level) * indentStepWidth
                let guideRect = NSRect(x: x, y: originY, width: 1.0, height: frame.height)
                let color = (level == activeIndentLevel) ? activeIndentGuideColor : indentGuideColor
                color.setFill()
                guideRect.fill(using: .sourceOver)
            }
            return true
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func computeIndentLevel(for text: String) -> Int {
        var spaces = 0
        for char in text {
            if char == " " {
                spaces += 1
            } else if char == "\t" {
                spaces += tabWidth
            } else {
                break
            }
        }
        return spaces / tabWidth
    }
}
