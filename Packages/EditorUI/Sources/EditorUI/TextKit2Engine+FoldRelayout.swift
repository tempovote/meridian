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
    /// The `layoutViewport()` here does double duty: it re-lays the
    /// invalidated fragments *and* populates `viewportRange`, which the
    /// following `purgeStaleViewportFragmentLayers` step reads. That purge
    /// is what fixes the live-window post-fold glyph garbling — see its doc
    /// comment. A second `layoutViewport()` after the purge was tried and
    /// found redundant (verified by on-screen screenshot across fold /
    /// refold / foldAll+scroll-back): the purge's synthetic edit invalidates
    /// the range and `needsDisplay = true` drives the final relayout on the
    /// display pass, so one explicit `layoutViewport()` suffices.
    func relayoutForFoldChange() {
        guard let tlm = textView.textLayoutManager else { return }
        tlm.invalidateLayout(for: tlm.documentRange)
        tlm.textViewportLayoutController.layoutViewport()
        purgeStaleViewportFragmentLayers(tlm)
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
    ///
    /// Scope is deliberately the *current viewport only*, even for whole-
    /// document ops like `foldAll()`/`foldLevel()` that collapse regions far
    /// off-screen. Those off-screen regions need no purge here: TextKit 2
    /// discards out-of-viewport fragments and re-vends them fresh when they
    /// scroll back in, so their layers are never stale. Verified on-screen
    /// with a ~240-line file — render all regions once by scrolling top to
    /// bottom, `foldAll()` while parked at the bottom (so only the bottom
    /// viewport is purged here), then scroll back up: every folded region,
    /// including the ones never in this purge's range, rendered clean.
    private func purgeStaleViewportFragmentLayers(_ tlm: NSTextLayoutManager) {
        guard let viewport = tlm.textViewportLayoutController.viewportRange else { return }
        let start = tlm.offset(from: tlm.documentRange.location, to: viewport.location)
        let end = tlm.offset(from: tlm.documentRange.location, to: viewport.endLocation)
        let range = NSRange(location: start, length: max(0, end - start))
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        // Defense-in-depth: the `.editedCharacters` delegate guard already
        // bails on this attribute-only edit, but flag it as our own mirror
        // write so a future reorder can't silently reintroduce phantom-edit
        // risk. Restore (not force-false) in case a caller nests.
        let wasMirroring = isMirroring
        isMirroring = true
        defer { isMirroring = wasMirroring }
        storage.beginEditing()
        storage.edited(.editedAttributes, range: range, changeInLength: 0)
        storage.endEditing()
    }
}
