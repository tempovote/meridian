import AppKit
import DocumentCore

extension TextKit2Engine: NSTextViewDelegate {
    /// See `documentUndoManager`'s doc comment: this is what actually
    /// routes Cmd+Z/Cmd+Shift+Z to the host's undo manager instead of the
    /// text view's own (empty, since `allowsUndo = false`) one.
    public func undoManager(for view: NSTextView) -> UndoManager? {
        documentUndoManager
    }

    public func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
        toCharacterRanges newSelectedCharRanges: [NSValue],
    ) -> [NSValue] {
        let oldR = oldSelectedCharRanges.map(\.rangeValue)
        let newR = newSelectedCharRanges.map(\.rangeValue)
        Swift.print("[Meridian Selection Debug] willChangeSelectionFromCharacterRanges: old=\(oldR) -> new=\(newR)")
        return newSelectedCharRanges
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        let ranges = textView.selectedRanges.map(\.rangeValue)
        Swift.print("[Meridian Selection Debug] textViewDidChangeSelection: currentRanges=\(ranges)")
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
        unfoldIfSelectionEnteredHiddenText()
        updateBracketHighlight()
    }
}

extension TextKit2Engine: NSTextStorageDelegate {
    /// Unisolated ObjC protocol requirement — AppKit always calls it on
    /// the main thread for a main-thread text view (ADR 0009 pattern:
    /// assert + `MainActor.assumeIsolated` to bridge into the class's
    /// `@MainActor` state). Capturing `self` directly in the closure is
    /// fine here — `TextKit2Engine` is a `@MainActor`-isolated `final`
    /// class, so it is implicitly `Sendable`; on this toolchain the
    /// `nonisolated(unsafe) let unsafeSelf = self` indirection the brief
    /// anticipated (for compilers whose region-based checker rejects
    /// capturing `self`) is flagged as unnecessary and, under this repo's
    /// `-warnings-as-errors` CI gate, must be omitted.
    public nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int,
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        assert(Thread.isMainThread, "NSTextStorageDelegate off the main thread")
        MainActor.assumeIsolated {
            guard !isMirroring else { return }
            handleUserEdit(newRange: editedRange, changeInLength: delta)
        }
    }
}

extension TextKit2Engine {
    /// Converts an observed user-initiated storage change into an
    /// ``EditTransaction`` against the pre-edit snapshot, advances the
    /// snapshot, and reports it.
    func handleUserEdit(newRange editedRange: NSRange, changeInLength delta: Int) {
        let oldLength = editedRange.length - delta
        let oldStart = buffer.byteOffset(of: UTF16Offset(editedRange.location))
        let oldEnd = buffer.byteOffset(of: UTF16Offset(editedRange.location + oldLength))
        let replacement = (storage.string as NSString).substring(with: editedRange)
        let key: CoalescingKey? = if oldLength == 0, !replacement.isEmpty {
            .typing
        } else if replacement.isEmpty, oldLength > 0 {
            .deleting
        } else {
            nil
        }
        let caretAfter = ByteOffset(oldStart.value + replacement.utf8.count)
        let transaction = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: oldStart ..< oldEnd, replacement: replacement)],
            selectionBefore: SelectionSet(caretAt: oldStart),
            selectionAfter: SelectionSet(caretAt: caretAfter),
            coalescingKey: key,
            origin: .user,
        )
        buffer.apply(transaction)
        assertMirrorInvariant()
        let foldedBefore = foldModel.folded
        foldModel.apply(transaction)
        if foldModel.folded != foldedBefore {
            // Deferred, not `refreshFoldLayout()`: we're still inside
            // `NSTextStorageDelegate.didProcessEditing`'s callstack here —
            // see `refreshFoldLayoutDeferred()`'s doc comment.
            refreshFoldLayoutDeferred()
        }
        highlightCurrentBuffer()
        onUserEdit?(transaction)
    }
}
