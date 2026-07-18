import AppKit
import DocumentCore

/// Custom TextKit 2 viewport view: NSTextLayoutManager +
/// NSTextViewportLayoutController drawing layout fragments directly.
/// Document height is estimated as lineCount × lineHeight (O(1) from rope
/// metadata) and never corrected downward mid-scroll (scrollbar stability
/// beats exactness in the spike).
@MainActor
final class ViewportView: NSView {
    let contentManager: RopeContentManager
    let layoutManager = NSTextLayoutManager()
    let container: NSTextContainer
    var caretByte = ByteOffset(0)
    var onFrame: ((CFTimeInterval, CFTimeInterval) -> Void)?

    private var fragments: [NSTextLayoutFragment] = []
    private var displayLink: CADisplayLink?
    let lineHeight: CGFloat

    init(contentManager: RopeContentManager) {
        self.contentManager = contentManager
        let font = RopeContentManager.attributes[.font] as? NSFont
        guard let font else { preconditionFailure("attributes must carry a font") }
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        container = NSTextContainer(size: CGSize(width: 1200, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 5
        super.init(frame: .zero)
        contentManager.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        layoutManager.textViewportLayoutController.delegate = self
        wantsLayer = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var estimatedDocumentHeight: CGFloat {
        CGFloat(contentManager.buffer.lineCount) * lineHeight + 20
    }

    func startDisplayLink() {
        let link = displayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        onFrame?(link.timestamp, link.targetTimestamp)
        // Re-lay out the viewport every frame while scrolling; TextKit
        // decides internally what is dirty.
        layoutManager.textViewportLayoutController.layoutViewport()
    }

    /// ⚠️ CRASHES — DO NOT CALL. `relocateViewport(to:)` (and every tested
    /// alternative) throws an uncatchable NSInvalidArgumentException inside
    /// AppKit's private `NSCountableTextLocation.compare:` when the content
    /// manager uses a custom NSTextLocation. Proven impossible in the Task 4
    /// jump investigation (see task-4-report.md / ADR 0009); kept only as
    /// evidence of the attempted approach. Task 5's benchmark drops its
    /// jump phase because of this.
    func jump(toLine line: Int) {
        let clamped = max(0, min(line, contentManager.buffer.lineCount - 1))
        let byte = contentManager.buffer.byteRange(ofLine: clamped).lowerBound
        scroll(NSPoint(x: 0, y: CGFloat(clamped) * lineHeight))
        layoutManager.textViewportLayoutController.relocateViewport(to: RopeLocation(byte))
    }

    // MARK: Input (interactive mode)

    override func keyDown(with event: NSEvent) {
        let buffer = contentManager.buffer
        if event.keyCode == 51 { // delete
            guard caretByte.value > 0 else { return }
            var prev = caretByte.value - 1
            while prev > 0, !buffer.isScalarBoundary(ByteOffset(prev)) { prev -= 1 }
            contentManager.applyEdit(replacing: ByteOffset(prev) ..< caretByte, with: "")
            caretByte = ByteOffset(prev)
        } else if let chars = event.characters, !chars.isEmpty,
                  chars.allSatisfy({ !$0.isASCII || $0.asciiValue.map { $0 >= 0x20 } == true || $0 == "\r" }) {
            let insert = chars == "\r" ? "\n" : chars
            contentManager.applyEdit(replacing: caretByte ..< caretByte, with: insert)
            caretByte = ByteOffset(caretByte.value + insert.utf8.count)
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let line = max(0, min(Int(point.y / lineHeight), contentManager.buffer.lineCount - 1))
        caretByte = contentManager.buffer.byteRange(ofLine: line).lowerBound
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        for fragment in fragments {
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
        }
        // Caret: 2px bar at the caret line's y (no column precision — spike).
        let caretLine = contentManager.buffer.linePosition(of: caretByte).line
        NSColor.systemRed.setFill()
        NSRect(x: 2, y: CGFloat(caretLine) * lineHeight, width: 2, height: lineHeight).fill()
    }
}

// DEVIATION (spike finding, Task 4): like RopeContentManager's
// NSTextElementProvider overrides (Task 2), NSTextViewportLayoutControllerDelegate
// is an ObjC protocol whose requirements are `nonisolated` regardless of the
// conforming class's `@MainActor` annotation — the compiler rejects the
// straightforward `@MainActor`-inferred conformance with
// "conformance ... crosses into main actor-isolated code and can cause data
// races" (#ConformanceIsolation). Fix: each requirement is `nonisolated` and
// bridges into the class's actual MainActor-isolated state via
// `MainActor.assumeIsolated`. This is sound for the same reason as Task 2:
// NSTextViewportLayoutController invokes its delegate synchronously on the
// thread that owns the layout manager (main, for app UI), so by the time
// these run we are in fact already on the main thread.
//
// DEVIATION from Task 2's exact pattern: Task 2's comment on
// `replaceContents` states a plain `self` alias cannot cross into the
// `@MainActor` closure and requires `nonisolated(unsafe)`. That does NOT
// reproduce here — `final class ViewportView: NSView` is a `@MainActor`
// type with no other non-Sendable stored state the compiler can see through
// on this path, and the compiler infers it Sendable for this purpose;
// `nonisolated(unsafe) let unsafeSelf = self` here compiles but with an
// explicit warning ("'nonisolated(unsafe)' is unnecessary for a constant
// with 'Sendable' type 'ViewportView'"), so it's omitted below. The
// `NSTextLayoutFragment` parameter is different: it genuinely needs
// `nonisolated(unsafe)` to cross into the closure (no warning fires),
// confirming it is not inferred Sendable. Net finding: whether the "sending
// self" workaround is needed is call-site-dependent, not a blanket rule —
// each conformance must be checked individually rather than assumed to
// need the full Task 2 treatment.
extension ViewportView: NSTextViewportLayoutControllerDelegate {
    nonisolated func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        let unsafeSelf = self
        return MainActor.assumeIsolated {
            // Visible rect + one viewport of overscan in each direction.
            let visible = unsafeSelf.enclosingScrollView?.documentVisibleRect ?? unsafeSelf.bounds
            return visible.insetBy(dx: 0, dy: -visible.height)
        }
    }

    nonisolated func textViewportLayoutControllerWillLayout(_ controller: NSTextViewportLayoutController) {
        let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf.fragments.removeAll(keepingCapacity: true)
        }
    }

    nonisolated func textViewportLayoutController(
        _ controller: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment,
    ) {
        let unsafeSelf = self
        nonisolated(unsafe) let unsafeFragment = textLayoutFragment
        MainActor.assumeIsolated {
            unsafeSelf.fragments.append(unsafeFragment)
        }
    }

    nonisolated func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf.needsDisplay = true
        }
    }
}
