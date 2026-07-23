import AppKit
import DocumentCore

/// A layout fragment that renders at zero height and draws nothing while
/// its paragraph lies in a folded (hidden) line span, and at its natural
/// size/appearance otherwise. The text element itself is untouched — the
/// content layer never learns about folding (spec: no new coordinate
/// space).
///
/// Folded state is re-evaluated on every access rather than fixed at
/// vend time: `NSTextLayoutManager` caches a fragment's identity across
/// `invalidateLayout`/relayout passes and only asks the layout-manager
/// delegate to vend a *new* fragment when the underlying text content
/// changes — never merely because `hiddenUTF16Spans` changed. A vend-time
/// choice between two fragment classes (one always-hidden, one always-
/// visible) would therefore latch a line's folded state permanently the
/// first time it is laid out, and unfolding would never take effect. This
/// single class checks live state each time instead, which TextKit 2 does
/// re-invoke (confirmed: `layoutFragmentFrame` recomputes across
/// `invalidateLayout` passes even though the fragment instance itself is
/// reused).
final class FoldAwareTextLayoutFragment: NSTextLayoutFragment {
    weak var engine: TextKit2Engine?

    override var layoutFragmentFrame: CGRect {
        let natural = super.layoutFragmentFrame
        guard isFolded else { return natural }
        var collapsed = natural
        collapsed.size.height = 0
        return collapsed
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard !isFolded else { return }
        super.draw(at: point, in: context)
    }

    private var isFolded: Bool {
        guard let engine, let tlm = textLayoutManager else { return false }
        let offset = tlm.offset(from: tlm.documentRange.location, to: rangeInElement.location)
        // `engine` is a `@MainActor` final class and therefore implicitly
        // `Sendable` (same reasoning as the `NSTextStorageDelegate`
        // conformance's doc comment below); `offset`/the `Bool` result are
        // plain `Sendable` values, so this crossing is safe with no
        // `nonisolated(unsafe)` needed. We are always called from AppKit's
        // main-thread layout pass, so this is a same-thread call, not an
        // actual hop.
        assert(Thread.isMainThread, "NSTextLayoutFragment folded check off the main thread")
        return MainActor.assumeIsolated {
            engine.isHiddenParagraph(startingAt: offset)
        }
    }
}

extension TextKit2Engine {
    /// Replaces the set of hidden line spans (0-based, end-exclusive) and
    /// forces a viewport relayout. The single choke point for fold
    /// visibility changes — later fold operations all funnel through here.
    func setHiddenLineSpans(_ spans: [Range<Int>]) {
        hiddenUTF16Spans = spans.compactMap { span in
            guard span.lowerBound < buffer.lineCount else { return nil }
            let startByte = buffer.byteRange(ofLine: span.lowerBound).lowerBound
            let endLine = min(span.upperBound, buffer.lineCount) - 1
            let endByte = buffer.byteRange(ofLine: endLine).upperBound
            let start = buffer.utf16Offset(of: startByte).value
            let end = buffer.utf16Offset(of: endByte).value
            return start ..< end
        }.sorted { $0.lowerBound < $1.lowerBound }
        // `FoldAwareTextLayoutFragment.isFolded` re-derives its state from
        // `hiddenUTF16Spans` on every access, so invalidating layout
        // (forcing existing fragments to recompute their frames) is enough
        // — no re-vend from the delegate is required or, per the class doc
        // comment above, even obtainable here.
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
        }
        refreshViewportLayout()
    }

    /// True when the paragraph starting at UTF-16 offset `offset` lies in a
    /// hidden span. Binary search over the sorted spans.
    func isHiddenParagraph(startingAt offset: Int) -> Bool {
        var low = 0, high = hiddenUTF16Spans.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let span = hiddenUTF16Spans[mid]
            if offset < span.lowerBound {
                high = mid - 1
            } else if offset >= span.upperBound {
                low = mid + 1
            } else {
                return true
            }
        }
        return false
    }
}

extension TextKit2Engine: NSTextLayoutManagerDelegate {
    /// Always vends the same fold-aware fragment class for every paragraph
    /// — see `FoldAwareTextLayoutFragment`'s doc comment for why the
    /// hidden/visible decision cannot be made here, at vend time.
    public nonisolated func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement,
    ) -> NSTextLayoutFragment {
        let fragment = FoldAwareTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.engine = self
        return fragment
    }
}
