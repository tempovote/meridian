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

public extension TextKit2Engine {
    /// Replaces the set of hidden line spans (0-based, end-exclusive) and
    /// forces a fold-only relayout (see `relayoutForFoldChange` below). The
    /// single choke point for fold visibility changes — later fold
    /// operations all funnel through here.
    internal func setHiddenLineSpans(_ spans: [Range<Int>]) {
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
    internal static func mergeSortedSpans(_ sorted: [Range<Int>]) -> [Range<Int>] {
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
    internal func isHiddenParagraph(startingAt offset: Int) -> Bool {
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
    internal func refreshFoldLayout() {
        setHiddenLineSpans(foldModel.hiddenLineSpans(in: buffer))
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
    internal func refreshFoldLayoutDeferred() {
        storeHiddenLineSpans(foldModel.hiddenLineSpans(in: buffer))
        guard !hasPendingDeferredFoldRelayout else { return }
        hasPendingDeferredFoldRelayout = true
        deferredFoldRelayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            hasPendingDeferredFoldRelayout = false
            relayoutForFoldChange()
        }
    }

    private var caretByteOffset: ByteOffset? {
        let ranges = textView.selectedRanges.map(\.rangeValue)
        guard ranges.count == 1, let sel = ranges.first, sel.length == 0,
              sel.location <= buffer.utf16Count else { return nil }
        return buffer.byteOffset(of: UTF16Offset(sel.location))
    }

    /// Folds the innermost foldable region containing the caret line.
    func foldAtCaret() {
        guard let caret = caretByteOffset else { return }
        let line = buffer.linePosition(of: caret).line
        guard let region = foldModel.foldableRegion(atLine: line) else { return }
        foldModel.fold(region)
        refreshFoldLayout()
    }

    /// Unfolds at the caret: innermost folded region containing the caret.
    func unfoldAtCaret() {
        guard let caret = caretByteOffset else { return }
        // Innermost folded region whose first line or body contains the caret.
        let line = buffer.linePosition(of: caret).line
        guard let region = foldModel.foldableRegion(atLine: line),
              foldModel.folded.contains(region.range)
        else {
            foldModel.unfoldEnclosing(caret)
            refreshFoldLayout()
            return
        }
        foldModel.unfold(startingAt: region.range.lowerBound)
        refreshFoldLayout()
    }

    func foldAll() {
        foldModel.foldAll()
        refreshFoldLayout()
    }

    func unfoldAll() {
        foldModel.unfoldAll()
        refreshFoldLayout()
    }

    /// Spec Fold Level N semantics (fold depth==n, unfold shallower).
    func foldLevel(_ level: Int) {
        foldModel.foldLevel(level)
        refreshFoldLayout()
    }

    /// Menu validation: is there a foldable region at the caret?
    var canFoldAtCaret: Bool {
        guard let caret = caretByteOffset else { return false }
        return foldModel.foldableRegion(atLine: buffer.linePosition(of: caret).line) != nil
    }

    var canUnfoldAtCaret: Bool {
        guard let caret = caretByteOffset else { return false }
        if foldModel.isInsideHiddenText(caret, in: buffer) {
            return true
        }
        let line = buffer.linePosition(of: caret).line
        guard let region = foldModel.foldableRegion(atLine: line) else { return false }
        return foldModel.folded.contains(region.range)
    }

    /// Caret-in-hidden-text guard (spec: "caret/edits never land inside
    /// hidden text"): any selection change whose caret ends up inside a
    /// folded body — goto-line, find navigation, character-wise arrow
    /// movement — unfolds the enclosing chain. Vertical arrow movement
    /// skips folds geometrically (zero-height fragments) and never
    /// triggers this.
    internal func unfoldIfSelectionEnteredHiddenText() {
        guard storage.length == buffer.utf16Count
        else { return } // mid-transaction guard, same as updateBracketHighlight
        guard let caret = caretByteOffset,
              foldModel.isInsideHiddenText(caret, in: buffer) else { return }
        foldModel.unfoldEnclosing(caret)
        refreshFoldLayout()
    }

    /// Wires the ruler's chevron gutter and the text view's `…` placeholder
    /// click to this engine's fold state. Called once from `init` — split
    /// out of `TextKit2Engine.swift` to keep that file under the swiftlint
    /// `file_length` limit.
    internal func configureFoldGutter() {
        rulerView?.foldMarkProvider = { [weak self] line in
            guard let self else { return .none }
            return foldModel.gutterMark(atLine: line, in: buffer)
        }
        rulerView?.onFoldChevronClick = { [weak self] line in
            self?.toggleFold(atLine: line)
        }
        textView.onFoldPlaceholderClick = { [weak self] point in
            self?.handleFoldPlaceholderClick(at: point) ?? false
        }
    }

    /// Chevron click: folds an unfolded foldable region at `line`, or
    /// unfolds an already-folded one. A no-op if `line` has no foldable
    /// region (a stale click racing a reparse — see the `gutterMark`
    /// staleness note above).
    private func toggleFold(atLine line: Int) {
        guard let region = foldModel.foldableRegion(atLine: line) else { return }
        if foldModel.folded.contains(region.range) {
            foldModel.unfold(startingAt: region.range.lowerBound)
        } else {
            foldModel.fold(region)
        }
        refreshFoldLayout()
    }

    /// Hit-tests a click in `textView`'s local coordinates against the `…`
    /// badge drawn past a folded first line's text (see
    /// `FoldAwareTextLayoutFragment.drawEllipsisBadge`); unfolds and
    /// returns true if the click landed on the badge. Mirrors the ruler's
    /// point → container-space conversion (`LineNumberRulerView
    /// .mouseDown`'s doc comment), but with no extra ruler-to-text-view
    /// hop since the click already originates in `textView`.
    private func handleFoldPlaceholderClick(at point: NSPoint) -> Bool {
        guard let tlm = textView.textLayoutManager else { return false }
        let pointInContainer = NSPoint(x: point.x, y: point.y - textView.textContainerOrigin.y)
        guard let fragment = tlm.textLayoutFragment(for: pointInContainer) else { return false }
        let offset = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
        guard let regionStart = foldedFirstLineUTF16Starts[offset] else { return false }
        let lineMaxX = fragment.textLineFragments.last.map(\.typographicBounds.maxX) ?? 0
        let localX = pointInContainer.x - fragment.layoutFragmentFrame.origin.x
        guard localX > lineMaxX else { return false }
        foldModel.unfold(startingAt: regionStart)
        refreshFoldLayout()
        return true
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
