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

    /// Draws normally when visible; when this fragment is the still-
    /// visible first line of a folded region, additionally appends a "…"
    /// badge past the line's typographic end. Same "re-evaluate live, no
    /// second class" reasoning as `isFolded` below applies here too — the
    /// badge must appear/disappear as folds toggle without TextKit 2 ever
    /// re-vending this fragment.
    override func draw(at point: CGPoint, in context: CGContext) {
        guard !isFolded else { return }
        super.draw(at: point, in: context)
        if isFoldedFirstLine {
            drawEllipsisBadge(at: point, in: context)
        }
    }

    /// This fragment's paragraph-start offset in document UTF-16
    /// coordinates — the shared lookup key for both `isFolded` and
    /// `isFoldedFirstLine`.
    private var documentOffset: Int? {
        guard let tlm = textLayoutManager else { return nil }
        return tlm.offset(from: tlm.documentRange.location, to: rangeInElement.location)
    }

    private var isFolded: Bool {
        guard let engine, let offset = documentOffset else { return false }
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

    /// True when this fragment is the visible first line of a currently
    /// folded region (see `TextKit2Engine.foldedFirstLineUTF16Starts`'s
    /// doc comment for how the lookup is kept in sync).
    private var isFoldedFirstLine: Bool {
        guard let engine, let offset = documentOffset else { return false }
        assert(Thread.isMainThread, "NSTextLayoutFragment folded check off the main thread")
        return MainActor.assumeIsolated {
            engine.foldedFirstLineUTF16Starts[offset] != nil
        }
    }

    private func drawEllipsisBadge(at point: CGPoint, in context: CGContext) {
        let badge = NSAttributedString(string: " …", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let lineWidth = textLineFragments.last.map(\.typographicBounds.maxX) ?? 0
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        badge.draw(at: CGPoint(x: point.x + lineWidth + 4, y: point.y))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Hidden-line-span state management (`hiddenUTF16Spans`/
/// `foldedFirstLineUTF16Starts`, kept in lockstep) and the TextKit 2
/// relayout choke points that consume it. Split out of
/// `TextKit2Engine+Folding.swift` (which keeps the fold *operations* —
/// `foldAtCaret` etc. — and the gutter/placeholder click wiring) purely to
/// stay under the swiftlint `file_length` limit.
extension TextKit2Engine {
    /// Replaces the set of hidden line spans (0-based, end-exclusive) and
    /// forces a fold-only relayout (see `relayoutForFoldChange` below). The
    /// single choke point for fold visibility changes — later fold
    /// operations all funnel through here.
    func setHiddenLineSpans(_ spans: [Range<Int>]) {
        storeHiddenLineSpans(spans)
        relayoutForFoldChange()
    }

    /// The pure-state half of `setHiddenLineSpans`: computes and stores
    /// `hiddenUTF16Spans` without touching TextKit 2 layout. Split out so
    /// `refreshFoldLayoutDeferred()` can update this synchronously (cheap,
    /// no AppKit calls) while still deferring the actual relayout pass —
    /// see that method's doc comment.
    private func storeHiddenLineSpans(_ spans: [Range<Int>]) {
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
        // Derived from `foldModel.folded` directly (not from `spans`):
        // production callers always pass `foldModel.hiddenLineSpans(in:
        // buffer)` here, so the two are in lockstep, but going straight to
        // the source avoids re-deriving a region's first line from a
        // merged span (multiple folds can merge into one span, losing
        // per-region identity). `unfold(startingAt:)` needs the region's
        // byte lower bound, not the line-space span, hence the `ByteOffset`
        // value.
        foldedFirstLineUTF16Starts = Dictionary(
            foldModel.folded.compactMap { region -> (Int, ByteOffset)? in
                let firstLine = buffer.linePosition(of: region.lowerBound).line
                guard firstLine < buffer.lineCount else { return nil }
                let utf16Start = buffer.utf16Offset(of: buffer.byteRange(ofLine: firstLine).lowerBound).value
                return (utf16Start, region.lowerBound)
            },
            uniquingKeysWith: { first, _ in first },
        )
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

    /// Recomputes hidden spans from the fold model — the ONLY caller of
    /// `setHiddenLineSpans` after Task 5; every fold mutation funnels here.
    func refreshFoldLayout() {
        setHiddenLineSpans(foldModel.hiddenLineSpans(in: buffer))
    }

    /// Same effect as `refreshFoldLayout()`, but skips the actual TextKit 2
    /// relayout/purge pass (`relayoutForFoldChange()`, which invalidates and
    /// re-lays the whole viewport) when recomputing hidden spans from the
    /// fold model produces the SAME `hiddenUTF16Spans`/
    /// `foldedFirstLineUTF16Starts` as before. The post-parse path
    /// (`highlightCurrentBuffer`) calls this on every successful parse —
    /// i.e. on every keystroke in a document with a `languageID` — and the
    /// overwhelming majority of keystrokes touch no fold state at all, so
    /// this turns that into a cheap no-op instead of per-keystroke relayout
    /// churn. `foldableChanged` lets the caller still ask for a ruler
    /// redraw when only the chevron set moved (a foldable region appeared/
    /// vanished) without the hidden spans themselves changing — the fold
    /// mutation call sites (`foldAtCaret` etc.) always change `folded`, so
    /// they keep calling `refreshFoldLayout()` unconditionally instead.
    func refreshFoldLayoutIfChanged(foldableChanged: Bool) {
        let previousHidden = hiddenUTF16Spans
        let previousFirstLineStarts = foldedFirstLineUTF16Starts
        storeHiddenLineSpans(foldModel.hiddenLineSpans(in: buffer))
        if hiddenUTF16Spans != previousHidden || foldedFirstLineUTF16Starts != previousFirstLineStarts {
            relayoutForFoldChange()
        } else if foldableChanged {
            rulerView?.needsDisplay = true
        }
    }

    /// Same effect as `refreshFoldLayout()`, but safe to call from inside
    /// `NSTextStorageDelegate.didProcessEditing` (`handleUserEdit`'s real
    /// typing path): `NSTextStorage.replaceCharacters` invokes that
    /// delegate callback synchronously, still on the stack, before AppKit
    /// itself relayouts the edit — calling `relayoutForFoldChange()`
    /// (`invalidateLayout`/`layoutViewport`, which enumerate the content
    /// storage) from in there re-enters TextKit 2 mid-edit and trips
    /// `NSTextContentStorageBreakOnEnumerateWhileEditing`. `apply(_:base:)`
    /// never has this problem — it calls `setHiddenLineSpans` only after
    /// `performEditingTransaction`'s closure has already returned — so it
    /// keeps calling `refreshFoldLayout()` synchronously, unchanged.
    ///
    /// `hiddenUTF16Spans` itself (the state fold-aware fragments and
    /// `foldModelForTesting`/`hiddenUTF16SpansForTesting` observe) is still
    /// updated synchronously here — only the TextKit 2 relayout pass is
    /// deferred, coalesced via `hasPendingDeferredFoldRelayout` so a burst
    /// of edits before the hop fires still only relayouts once.
    func refreshFoldLayoutDeferred() {
        storeHiddenLineSpans(foldModel.hiddenLineSpans(in: buffer))
        guard !hasPendingDeferredFoldRelayout else { return }
        hasPendingDeferredFoldRelayout = true
        // Captured, not read fresh inside the `Task`: if `load(buffer:)`
        // adopts an entirely new buffer lineage before this hop runs (e.g.
        // an `NSDocument` revert racing a just-typed edit), the scheduled
        // relayout must no-op rather than operate against the new
        // document's already-reset fold state with stale intent.
        let scheduledGeneration = loadGeneration
        deferredFoldRelayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            hasPendingDeferredFoldRelayout = false
            guard loadGeneration == scheduledGeneration else { return }
            relayoutForFoldChange()
        }
    }
}
