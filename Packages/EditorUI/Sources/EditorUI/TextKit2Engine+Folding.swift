import AppKit
import DocumentCore

/// Fold *operations* (fold/unfold at caret, fold-all, fold-level) and the
/// gutter chevron / `…` placeholder click wiring. Hidden-span state
/// management and the underlying TextKit 2 relayout choke points live in
/// `TextKit2Engine+FoldSpans.swift` — split apart purely to stay under the
/// swiftlint `file_length` limit.
public extension TextKit2Engine {
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
        repositionCaretIfInsideHiddenText()
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
        repositionCaretIfInsideHiddenText()
    }

    func unfoldAll() {
        foldModel.unfoldAll()
        refreshFoldLayout()
    }

    /// Spec Fold Level N semantics (fold depth==n, unfold shallower).
    func foldLevel(_ level: Int) {
        foldModel.foldLevel(level)
        refreshFoldLayout()
        repositionCaretIfInsideHiddenText()
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
        repositionCaretIfInsideHiddenText()
    }

    /// Shared post-fold-mutation guard (spec invariant: "caret never lands
    /// inside hidden text"): if the caret ended up buried inside a region
    /// this operation just folded, moves it to the end of the innermost
    /// enclosing region's visible first line — standard Notepad++/VS Code
    /// behavior. Without this, the caret sits invisible in hidden text and
    /// the very next selection change trips
    /// `unfoldIfSelectionEnteredHiddenText`, silently reverting the fold
    /// the user just requested. A no-op (correctly) whenever the caret
    /// isn't inside hidden text — including every `unfold*` call site,
    /// which never need to call this.
    ///
    /// Resolves the FINAL target line entirely in `FoldModel`/`buffer`
    /// terms before ever touching the real selection, and calls
    /// `setSelection` exactly once. This matters for NESTED folds: e.g.
    /// after `foldAll()`/`foldLevel()` folds both an outer block and the
    /// caret's inner block at once, the innermost enclosing region's own
    /// first line is itself hidden inside the OUTER fold. Calling
    /// `setSelection` at that intermediate (still-hidden) position would
    /// synchronously fire `textViewDidChangeSelection` ->
    /// `unfoldIfSelectionEnteredHiddenText`, which would immediately
    /// unfold the whole enclosing chain — undoing the very fold(s) this
    /// operation just applied. Walking outward first and only committing
    /// the final, genuinely-visible line avoids that. Bounded by
    /// `folded.count`: each hop strictly widens to a shallower enclosing
    /// region, so it terminates within that many iterations even against
    /// `FoldModel`'s legally-permitted overlapping regions.
    private func repositionCaretIfInsideHiddenText() {
        guard let originalCaret = caretByteOffset, foldModel.isInsideHiddenText(originalCaret, in: buffer)
        else { return }
        var caret = originalCaret
        var remainingHops = foldModel.folded.count
        while remainingHops > 0, foldModel.isInsideHiddenText(caret, in: buffer) {
            remainingHops -= 1
            let line = buffer.linePosition(of: caret).line
            guard let region = foldModel.foldedRegionHidingLine(line, in: buffer) else { break }
            let startLine = buffer.linePosition(of: region.lowerBound).line
            caret = buffer.byteRange(ofLine: startLine).upperBound
        }
        setSelection(SelectionSet(caretAt: caret), in: buffer)
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
