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

    // MARK: - Multi-Caret Support

    /// Stores multiple caret ranges that AppKit would otherwise discard.
    /// AppKit's `NSTextView` silently collapses zero-length (insertion-point)
    /// ranges to a single cursor when `selectedRanges` is set with multiple
    /// entries. We preserve the full list here and return it from the getter.
    private var customSelectedRanges: [NSValue]?

    /// Set to `true` only while WE are deliberately applying a multi-caret
    /// selection. During that window, AppKit's own internal re-entrant
    /// `setSelectedRanges` calls must NOT clear `customSelectedRanges`.
    private var isSettingMultiCaret: Bool = false

    /// Applies `ranges` as a persistent multi-caret selection.
    /// Use this instead of assigning `selectedRanges` directly when
    /// `ranges.count > 1`.
    public func applyMultiCaretRanges(_ ranges: [NSValue]) {
        guard ranges.count > 1 else {
            // Single caret — clear multi-caret state and let AppKit handle it.
            customSelectedRanges = nil
            super.selectedRanges = ranges
            return
        }
        isSettingMultiCaret = true
        customSelectedRanges = ranges
        super.selectedRanges = ranges
        isSettingMultiCaret = false
    }

    override public var selectedRanges: [NSValue] {
        get {
            customSelectedRanges ?? super.selectedRanges
        }
        set {
            // Route through applyMultiCaretRanges so multi-caret intent is
            // always declared explicitly.
            applyMultiCaretRanges(newValue)
        }
    }

    override public func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool,
    ) {
        if ranges.count > 1 {
            // Explicit multi-caret call from our own code.
            isSettingMultiCaret = true
            customSelectedRanges = ranges
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            isSettingMultiCaret = false
        } else if isSettingMultiCaret {
            // AppKit's own internal re-entrant call during our multi-caret
            // apply — let it through but keep customSelectedRanges intact.
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        } else if customSelectedRanges != nil {
            // AppKit is trying to collapse our multi-caret to a single range
            // (e.g. cursor-blink timer, internal layout pass). Suppress it.
            return
        } else {
            // Normal single-caret path.
            customSelectedRanges = nil
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        }
    }

    // MARK: - First Responder

    override public func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onBecomeFirstResponder?()
        }
        return result
    }

    // MARK: - Key Events

    override public func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.option, .command] {
            if event.keyCode == 126 { // Up arrow
                NSApp.sendAction(#selector(addCaretAbove(_:)), to: nil, from: self)
                return
            } else if event.keyCode == 125 { // Down arrow
                NSApp.sendAction(#selector(addCaretBelow(_:)), to: nil, from: self)
                return
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Add Caret Actions

    /// Set by `TextKit2Engine`: handles Option+Cmd+Up action.
    public var onAddCaretAbove: (() -> Void)?
    /// Set by `TextKit2Engine`: handles Option+Cmd+Down action.
    public var onAddCaretBelow: (() -> Void)?

    @objc public func addCaretAbove(_ sender: Any?) {
        onAddCaretAbove?()
    }

    @objc public func addCaretBelow(_ sender: Any?) {
        onAddCaretBelow?()
    }

    // MARK: - Mouse Events

    override public func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if onFoldPlaceholderClick?(point) == true {
            return
        }
        if flags.contains(.option) || flags.contains(.command) {
            if window?.firstResponder != self {
                window?.makeFirstResponder(self)
            }
            onOptionClick?(point)
            return
        }
        // Plain click: explicitly clear multi-caret state so AppKit can
        // position a single cursor normally.
        customSelectedRanges = nil
        super.mouseDown(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Suppress mouseUp only for modifier-based clicks (Option/Command add caret)
        // so AppKit does not move the insertion point after we placed a new caret.
        if flags.contains(.option) || flags.contains(.command) {
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: - Drawing

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
        guard ranges.count > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        let caretColor = insertionPointColor ?? NSColor.controlAccentColor
        caretColor.setFill()

        for selected in ranges where selected.length == 0 {
            guard let caretRect = caretRect(for: selected) else { continue }
            if caretRect.intersects(rect) {
                caretRect.fill()
            }
        }
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
            let lowerBound = lineRange.location
            let upperBound = lineRange.location + lineRange.length
            if charOffsetInElement >= lowerBound,
               charOffsetInElement <= upperBound
            {
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
