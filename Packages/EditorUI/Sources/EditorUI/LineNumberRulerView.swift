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
        let newThickness = max(40, ceil(width + 16))
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

        let textContainerOrigin = textView.textContainerOrigin
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]

        var lastDrawnLine: Int?

        // Enumerate text layout fragments
        let docRange = textLayoutManager.documentRange
        textLayoutManager.enumerateTextLayoutFragments(
            from: docRange.location,
            options: [.ensuresLayout, .estimatesSize],
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let viewY = frame.origin.y + textContainerOrigin.y
            let fragmentRectInTextView = NSRect(x: 0, y: viewY, width: 1, height: frame.height)
            let fragmentRectInRuler = self.convert(fragmentRectInTextView, from: textView)

            // Skip if completely outside the redraw rect
            if fragmentRectInRuler.maxY < rect.minY || fragmentRectInRuler.minY > rect.maxY {
                return true
            }

            // Find line number for fragment start
            let docStart = docRange.location
            let offsetInUTF16 = textLayoutManager.offset(from: docStart, to: fragment.rangeInElement.location)
            let byteOffset = buffer.byteOffset(of: UTF16Offset(offsetInUTF16))
            let linePos = buffer.linePosition(of: byteOffset)

            let labelText: String
            if lastDrawnLine != linePos.line {
                labelText = String(linePos.line + 1)
                lastDrawnLine = linePos.line
            } else {
                labelText = self.continuationSymbol
            }

            let attrString = NSAttributedString(string: labelText, attributes: textAttributes)
            let labelSize = attrString.size()
            let drawX = self.ruleThickness - labelSize.width - 8
            let drawY = fragmentRectInRuler.minY + (fragmentRectInRuler.height - labelSize.height) / 2

            attrString.draw(at: NSPoint(x: drawX, y: drawY))
            return true
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
