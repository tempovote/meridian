import AppKit
import DocumentCore

/// An `NSRulerView` subclass attached to `NSScrollView.verticalRulerView`
/// that renders 1-based line numbers in sync with TextKit 2 layout fragments.
@MainActor
public final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var bufferProvider: (() -> TextBuffer)?

    public var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet {
            updateThickness()
            needsDisplay = true
        }
    }

    public var textColor: NSColor = .secondaryLabelColor {
        didSet { needsDisplay = true }
    }

    public var separatorColor: NSColor = .gridColor {
        didSet { needsDisplay = true }
    }

    public var continuationSymbol: String = "·"

    /// Width reserved for fold chevrons at the trailing edge of the ruler,
    /// only when `foldMarkProvider` is set.
    private static let chevronBandWidth: CGFloat = 14

    /// Per-line fold gutter state; nil provider = no fold band (M7 CoreText
    /// engine, or gutter before folding data arrives).
    public var foldMarkProvider: ((Int) -> FoldGutterMark)? {
        didSet {
            updateThickness()
            needsDisplay = true
        }
    }

    /// Fired when the user clicks the chevron band on a line.
    public var onFoldChevronClick: ((Int) -> Void)?

    public init(scrollView: NSScrollView, textView: NSTextView, bufferProvider: @escaping () -> TextBuffer) {
        self.textView = textView
        self.bufferProvider = bufferProvider
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateThickness() {
        let lineCount = bufferProvider?().lineCount ?? 1
        let digits = max(3, String(lineCount).count)
        let sampleString = String(repeating: "8", count: digits) as NSString
        let width = sampleString.size(withAttributes: [.font: font]).width
        var newThickness = max(40, ceil(width + 16))
        if foldMarkProvider != nil {
            newThickness += Self.chevronBandWidth
        }
        if ruleThickness != newThickness {
            ruleThickness = newThickness
        }
    }

    private func drawBackgroundAndSeparator() {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        separatorColor.setStroke()
        let sepPath = NSBezierPath()
        sepPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        sepPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        sepPath.lineWidth = 1.0
        sepPath.stroke()
    }

    override public func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let textLayoutManager = textView.textLayoutManager,
              let buffer = bufferProvider?()
        else { return }

        updateThickness()

        NSGraphicsContext.saveGraphicsState()
        drawBackgroundAndSeparator()

        let context = LabelDrawContext(
            textView: textView,
            buffer: buffer,
            textLayoutManager: textLayoutManager,
            textAttributes: [.font: font, .foregroundColor: textColor],
        )
        var lastDrawnLine: Int?

        textLayoutManager.enumerateTextLayoutFragments(
            from: context.docRange.location,
            options: [.ensuresLayout, .estimatesSize],
        ) { fragment in
            self.drawLabel(for: fragment, in: rect, context, lastDrawnLine: &lastDrawnLine)
            return true
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    /// The parts of `drawHashMarksAndLabels`'s per-fragment draw that stay
    /// constant across the whole enumeration — bundled into one value so
    /// `drawLabel(for:in:_:lastDrawnLine:)` stays under swiftlint's
    /// `function_parameter_count` limit.
    private struct LabelDrawContext {
        let textView: NSTextView
        let buffer: TextBuffer
        let textLayoutManager: NSTextLayoutManager
        let textAttributes: [NSAttributedString.Key: Any]
        var docRange: NSTextRange {
            textLayoutManager.documentRange
        }
    }

    /// Draws one fragment's line number (or continuation dot) and, on the
    /// first fragment of a line, its fold chevron if any. Skips zero-
    /// height (folded) fragments and any fragment outside `rect`. Factored
    /// out of `drawHashMarksAndLabels` to keep that function under the
    /// swiftlint `function_body_length` limit.
    private func drawLabel(
        for fragment: NSTextLayoutFragment,
        in rect: NSRect,
        _ context: LabelDrawContext,
        lastDrawnLine: inout Int?,
    ) {
        let frame = fragment.layoutFragmentFrame
        // Folded-away lines produce zero-height fragments — skip them so
        // numbering jumps over hidden lines (10 → 42, Notepad++ style).
        guard frame.height > 0 else { return }

        let viewY = frame.origin.y + context.textView.textContainerOrigin.y
        let fragmentRectInTextView = NSRect(x: 0, y: viewY, width: 1, height: frame.height)
        let fragmentRectInRuler = convert(fragmentRectInTextView, from: context.textView)
        guard fragmentRectInRuler.maxY >= rect.minY, fragmentRectInRuler.minY <= rect.maxY else { return }

        let offsetInUTF16 = context.textLayoutManager.offset(
            from: context.docRange.location, to: fragment.rangeInElement.location,
        )
        let byteOffset = context.buffer.byteOffset(of: UTF16Offset(offsetInUTF16))
        let linePos = context.buffer.linePosition(of: byteOffset)

        let isFirstOfLine = lastDrawnLine != linePos.line
        let labelText = isFirstOfLine ? String(linePos.line + 1) : continuationSymbol
        if isFirstOfLine {
            lastDrawnLine = linePos.line
        }

        let bandOffset: CGFloat = foldMarkProvider != nil ? Self.chevronBandWidth : 0
        let attrString = NSAttributedString(string: labelText, attributes: context.textAttributes)
        let labelSize = attrString.size()
        let drawX = ruleThickness - bandOffset - labelSize.width - 8
        let drawY = fragmentRectInRuler.minY + (fragmentRectInRuler.height - labelSize.height) / 2
        attrString.draw(at: NSPoint(x: drawX, y: drawY))

        if isFirstOfLine, let mark = foldMarkProvider?(linePos.line), mark != .none {
            let symbol = mark == .folded ? "▸" : "▾"
            NSAttributedString(string: symbol, attributes: context.textAttributes)
                .draw(at: NSPoint(x: ruleThickness - Self.chevronBandWidth + 2, y: drawY))
        }
    }

    /// Chevron-band hit-testing: a click in the trailing `chevronBandWidth`
    /// strip resolves to the line under the cursor via the same fragment
    /// enumeration `drawHashMarksAndLabels` uses, and reports it through
    /// `onFoldChevronClick`. Any other click falls through to `super` for
    /// normal ruler behavior (there is none today, but this keeps the
    /// view a well-behaved `NSRulerView`).
    override public func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard foldMarkProvider != nil,
              localPoint.x >= ruleThickness - Self.chevronBandWidth,
              let textView,
              let textLayoutManager = textView.textLayoutManager,
              let buffer = bufferProvider?()
        else {
            super.mouseDown(with: event)
            return
        }
        // `drawHashMarksAndLabels` maps a fragment's container-space
        // `layoutFragmentFrame.origin.y` to ruler-space via
        // `viewY = frame.origin.y + textContainerOrigin.y` then `convert
        // (from: textView)`. Hit-testing inverts exactly that: ruler point
        // → text view point → subtract `textContainerOrigin.y` to land back
        // in the container space `textLayoutFragment(for:)` expects.
        let pointInTextView = textView.convert(localPoint, from: self)
        let pointInContainer = NSPoint(x: 0, y: pointInTextView.y - textView.textContainerOrigin.y)
        guard let fragment = textLayoutManager.textLayoutFragment(for: pointInContainer) else {
            super.mouseDown(with: event)
            return
        }
        let offset = textLayoutManager.offset(
            from: textLayoutManager.documentRange.location, to: fragment.rangeInElement.location,
        )
        let line = buffer.linePosition(of: buffer.byteOffset(of: UTF16Offset(offset))).line
        onFoldChevronClick?(line)
    }
}
