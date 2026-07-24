import AppKit
import DocumentCore

/// The component-level seam between the document model and its renderer
/// (ADR 0009). P1 ships ``TextKit2Engine``; M7 adds a CoreText-based
/// conformer for huge files. Chrome and ``EditorViewModel`` talk only
/// through this protocol — never to a concrete engine.
///
/// Contract: the engine mirrors the rope. After `load` or `apply`, the
/// rendered text equals the buffer's content byte-for-byte. User edits
/// made directly in the engine's view are reported through ``onUserEdit``
/// as transactions already applied to the engine's internal snapshot;
/// the receiver applies them to the authoritative buffer to stay in
/// lockstep and MUST NOT mirror them back via ``apply(_:base:)``.
@MainActor
public protocol TextLayoutEngine: AnyObject {
    /// The scrollable editor component to embed in a window.
    var view: NSView { get }

    /// The view that should receive keyboard focus (the text view itself,
    /// not its scroll-view wrapper) — pass to `makeFirstResponder`.
    var keyView: NSView { get }

    /// Fired once per user-initiated storage change (typing, paste, IME
    /// composition step), converted to rope coordinates against the
    /// engine's pre-edit snapshot.
    var onUserEdit: ((EditTransaction) -> Void)? { get set }

    /// Replaces all rendered content with `buffer`'s. Does not fire
    /// ``onUserEdit``.
    func load(buffer: TextBuffer)

    /// Mirrors a rope-side transaction into the renderer. `base` is the
    /// buffer BEFORE the transaction (needed for coordinate conversion).
    /// Does not fire ``onUserEdit``. `restoreSelection` controls whether
    /// the renderer's caret/selection moves to `transaction.selectionAfter`
    /// — pass `false` when this call is mirroring another pane's edit into
    /// a sibling pane that didn't originate it, where only the content
    /// should change and the sibling's own scroll/caret position must be
    /// left alone.
    func apply(_ transaction: EditTransaction, base: TextBuffer, restoreSelection: Bool)

    /// The current selection in rope coordinates. `buffer` must be the
    /// engine's current mirror content.
    func selection(in buffer: TextBuffer) -> SelectionSet

    /// Moves the selection. Ranges must lie on scalar boundaries within
    /// `buffer` (the engine's current mirror content).
    func setSelection(_ selection: SelectionSet, in buffer: TextBuffer)

    /// Scrolls so `offset` is visible.
    func scrollTo(_ offset: ByteOffset, in buffer: TextBuffer)

    /// Toggles soft wrap mode on the renderer.
    func setSoftWrap(_ enabled: Bool)

    /// Toggles visibility of the line number gutter.
    func setGutterVisible(_ enabled: Bool)

    /// Fired when this engine's view becomes the window's first
    /// responder — lets the host track which pane the user is currently
    /// interacting with (e.g. to drive which pane's state the status bar
    /// reflects, when a document has more than one pane open).
    var onBecomeFirstResponder: (() -> Void)? { get set }

    /// Folds the innermost foldable region containing the caret line.
    func foldAtCaret()
    /// Unfolds at the caret: innermost folded region containing the caret.
    func unfoldAtCaret()
    func foldAll()
    func unfoldAll()
    /// Spec Fold Level N semantics (fold depth==n, unfold shallower).
    func foldLevel(_ level: Int)
    /// Menu validation: is there a foldable region at the caret?
    var canFoldAtCaret: Bool { get }
    /// Menu validation: is there something to unfold at the caret?
    var canUnfoldAtCaret: Bool { get }
}

public extension TextLayoutEngine {
    func setSoftWrap(_ enabled: Bool) {}
    func setGutterVisible(_ enabled: Bool) {}

    // Folding no-op defaults: any conformer (e.g. a future M7 CoreText
    // engine) compiles without implementing folding until it's ready to.
    func foldAtCaret() {}
    func unfoldAtCaret() {}
    func foldAll() {}
    func unfoldAll() {}
    func foldLevel(_ level: Int) {}
    var canFoldAtCaret: Bool {
        false
    }

    var canUnfoldAtCaret: Bool {
        false
    }

    /// Convenience overload preserving every existing call site — always
    /// restores selection, matching this method's original (pre-split-editor)
    /// behavior.
    func apply(_ transaction: EditTransaction, base: TextBuffer) {
        apply(transaction, base: base, restoreSelection: true)
    }
}
