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
    /// forces a fold-only relayout (see `relayoutForFoldChange` below). The
    /// single choke point for fold visibility changes — later fold
    /// operations all funnel through here.
    func setHiddenLineSpans(_ spans: [Range<Int>]) {
        let converted: [Range<Int>] = spans.compactMap { span in
            // An empty span (e.g. `0..<0`) hides nothing; `endLine` below
            // would otherwise go negative and `byteRange(ofLine:)` would
            // trap. Guard it out before any coordinate conversion.
            guard !span.isEmpty, span.lowerBound < buffer.lineCount else { return nil }
            let startByte = buffer.byteRange(ofLine: span.lowerBound).lowerBound
            let start = buffer.utf16Offset(of: startByte).value
            let clampedUpperLine = min(span.upperBound, buffer.lineCount)
            // `byteRange(ofLine:)` excludes a line's trailing `\n`, so using
            // the *last hidden line's own* end would, for a blank last
            // line, equal that line's start — collapsing the span to empty
            // and leaving the blank line visible. Use the *next* line's
            // start instead (or the buffer's end, if the span reaches the
            // last line), which correctly includes the hidden lines'
            // trailing newlines up to the first non-hidden paragraph.
            let end = if clampedUpperLine < buffer.lineCount {
                buffer.utf16Offset(of: buffer.byteRange(ofLine: clampedUpperLine).lowerBound).value
            } else {
                buffer.utf16Count
            }
            return start ..< end
        }.sorted { $0.lowerBound < $1.lowerBound }
        // Fold spans may come from callers (e.g. a future `FoldModel`) that
        // don't guarantee disjointness — nested/overlapping regions are a
        // legitimate input, not a caller bug. `isHiddenParagraph`'s binary
        // search requires disjoint, sorted spans to be correct, so merge
        // overlapping/adjacent spans here, once, rather than pushing that
        // requirement onto every caller.
        hiddenUTF16Spans = Self.mergeSortedSpans(converted)
        relayoutForFoldChange()
    }

    /// Merges overlapping or adjacent ranges in an already-sorted-by-
    /// `lowerBound` array into the minimal disjoint set. `adjacent` here
    /// means touching (`a.upperBound == b.lowerBound`), not just
    /// overlapping — folding lines `0..<2` and `2..<4` should coalesce into
    /// one hidden run, not leave a zero-width gap `isHiddenParagraph` could
    /// disagree about.
    static func mergeSortedSpans(_ sorted: [Range<Int>]) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for span in sorted {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< Swift.max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// A lighter relayout than `refreshViewportLayout()`: invalidates
    /// layout and re-lays-out only the current viewport, without
    /// `ensureLayout(for: documentRange)`. Folding must not force a
    /// full-document layout pass on every toggle — that would defeat
    /// TextKit 2's viewport laziness on large files, turning an O(visible
    /// lines) operation into O(document lines). `refreshViewportLayout()`
    /// itself is intentionally left alone: the split-pane fresh-frame nudge
    /// it exists for genuinely needs the full-document `ensureLayout`.
    private func relayoutForFoldChange() {
        guard let tlm = textView.textLayoutManager else { return }
        tlm.invalidateLayout(for: tlm.documentRange)
        tlm.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
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
