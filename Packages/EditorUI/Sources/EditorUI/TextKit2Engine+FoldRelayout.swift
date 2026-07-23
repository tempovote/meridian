import AppKit

extension TextKit2Engine {
    /// A lighter relayout than `refreshViewportLayout()`: invalidates
    /// layout and re-lays-out only the current viewport, without
    /// `ensureLayout(for: documentRange)`. Folding must not force a
    /// full-document layout pass on every toggle — that would defeat
    /// TextKit 2's viewport laziness on large files, turning an O(visible
    /// lines) operation into O(document lines). `refreshViewportLayout()`
    /// itself is intentionally left alone: the split-pane fresh-frame nudge
    /// it exists for genuinely needs the full-document `ensureLayout`.
    ///
    /// The `purgeStaleViewportFragmentLayers` step in the middle is what
    /// fixes the live-window post-fold glyph garbling — see its doc comment.
    func relayoutForFoldChange() {
        guard let tlm = textView.textLayoutManager else { return }
        tlm.invalidateLayout(for: tlm.documentRange)
        tlm.textViewportLayoutController.layoutViewport()
        purgeStaleViewportFragmentLayers(tlm)
        tlm.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
    }

    /// Root-cause fix for the interactive-fold rendering defect: after a
    /// fragment collapses to zero height, the newly-visible row below it
    /// rendered with the just-hidden lines' glyphs superimposed.
    ///
    /// `invalidateLayout(for:)` deliberately *reuses* fragment identities
    /// across passes (that reuse is the whole basis of the dynamic
    /// `FoldAwareTextLayoutFragment` design). But in a live, layer-backed
    /// `NSTextView`, each fragment owns a cached CALayer holding its
    /// rendered glyphs; reusing the fragment reuses that stale layer, so the
    /// just-collapsed lines' layers linger on screen while the row below is
    /// composited over them. `invalidateLayout`, `ensureLayout`, explicit
    /// layer invalidation, and `displayIfNeeded` all failed to purge them
    /// (offscreen `cacheDisplay`, which bypasses the layer cache entirely,
    /// always rendered correctly — proving the fragment *frames* were right
    /// and only the live layer cache was stale).
    ///
    /// A *content-storage edit* is the one thing that makes
    /// `NSTextContentStorage` discard and re-vend the affected fragments,
    /// forcing `NSTextView` to build fresh layers for them. A zero-length
    /// `.editedAttributes` edit over the current viewport re-vends exactly
    /// the visible fragments (O(visible lines), not O(document)) without
    /// changing a single character or attribute — highlighting is
    /// untouched. `.editedAttributes` (not `.editedCharacters`) also means
    /// the `NSTextStorageDelegate` guard skips it, so it is never mistaken
    /// for a user edit. Safe from `BreakOnEnumerateWhileEditing`: every
    /// caller reaches here outside any editing transaction (fold actions
    /// call it directly; the typing path defers it to a `Task` hop).
    private func purgeStaleViewportFragmentLayers(_ tlm: NSTextLayoutManager) {
        guard let viewport = tlm.textViewportLayoutController.viewportRange else { return }
        let start = tlm.offset(from: tlm.documentRange.location, to: viewport.location)
        let end = tlm.offset(from: tlm.documentRange.location, to: viewport.endLocation)
        let range = NSRange(location: start, length: max(0, end - start))
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        storage.edited(.editedAttributes, range: range, changeInLength: 0)
        storage.endEditing()
    }
}
