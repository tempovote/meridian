import AppKit
import DocumentCore
import SettingsKit
import SyntaxKit
import ThemeKit

/// TextKit 2 conformer of ``TextLayoutEngine``: a standard `NSTextView`
/// backed by Apple's `NSTextContentStorage` (ADR 0009 verdict), with the
/// rope mirrored into `NSTextStorage`. The engine keeps its own
/// `TextBuffer` snapshot in lockstep with the storage so user edits can
/// be converted to rope coordinates against pre-edit content.
@MainActor
public final class TextKit2Engine: NSObject, TextLayoutEngine {
    private let scrollView: NSScrollView
    let textView: MeridianTextView
    private var rulerView: LineNumberRulerView?
    /// The engine-local mirror snapshot. Invariant: equals the storage's
    /// string after every load/apply/user edit. Only ever touched from
    /// within `MainActor.assumeIsolated` (directly, or via the `@MainActor`
    /// methods below), so no `nonisolated(unsafe)` escape hatch is needed —
    /// see the delegate override's doc comment for the isolation bridge.
    var buffer = TextBuffer()
    /// True while `load`/`apply` mutate the storage, so the delegate does
    /// not report our own mirroring as a user edit.
    var isMirroring = false
    /// Increments every time `load(buffer:)` adopts a brand-new buffer
    /// lineage (never on `apply`, which reuses the same lineage). Needed
    /// because `TextBuffer.version` resets to 0 for every new `TextBuffer`
    /// instance, so two different lineages can share a version number —
    /// `highlightCurrentBuffer()`'s staleness check must distinguish
    /// "later edit of the same lineage" from "an entirely different
    /// lineage that happens to share a version" (e.g. `NSDocument` revert
    /// calling `load(buffer:)` again on the same engine).
    var loadGeneration = 0

    let syntaxService = SyntaxService()
    let syntaxDocumentID = DocumentID()
    /// Detected once at `load(buffer:)` time from the document's file
    /// extension (set externally — see `languageID(forFileExtension:)`
    /// below); `nil` means "don't highlight".
    public var languageID: String?

    let themeEngine: ThemeEngine
    private let settingsStore: SettingsStore
    var fontCache: TokenFontCache
    var paragraphStyle: NSParagraphStyle
    /// The most recent token classification from `applyHighlighting`, kept
    /// around so bracket-match recomputation (on every selection change)
    /// doesn't need to reparse — `nil` until the first successful parse,
    /// or forever for a document with no `languageID`.
    var lastTokenRuns: [TokenRun]?
    /// The two byte ranges currently painted with the bracket-match
    /// background color, so they can be cleared before a new pair (or
    /// none) is painted.
    var currentBracketHighlightRanges: [NSRange] = []

    public var onUserEdit: ((EditTransaction) -> Void)?

    /// The undo manager Cmd+Z/Cmd+Shift+Z should resolve to. `NSTextView`
    /// implements `-undo:`/`-redo:`/`-undoManager` itself and answers them
    /// directly (against its own private undo manager if no delegate
    /// supplies one) rather than forwarding up the responder chain —
    /// `allowsUndo = false` only suppresses its *automatic registration* of
    /// edits, it does not stop it from intercepting the menu actions. So
    /// without this, Cmd+Z is silently swallowed by an empty manager the
    /// text view owns, and never reaches whatever the host (e.g.
    /// `NSDocument`) wires up as the real undo manager. Set by the host via
    /// this property; wired to `NSTextViewDelegate.undoManager(for:)`.
    public var documentUndoManager: UndoManager?

    public var view: NSView {
        scrollView
    }

    public var keyView: NSView {
        textView
    }

    /// Passthrough to `textView.onBecomeFirstResponder` — see
    /// `TextLayoutEngine.onBecomeFirstResponder`'s doc comment.
    public var onBecomeFirstResponder: (() -> Void)? {
        get { textView.onBecomeFirstResponder }
        set { textView.onBecomeFirstResponder = newValue }
    }

    /// Builds the scroll view + TextKit 2 text view, plain-text config.
    public init(themeEngine: ThemeEngine, settingsStore: SettingsStore) {
        self.themeEngine = themeEngine
        self.settingsStore = settingsStore
        let initialEditor = settingsStore.current.editor
        fontCache = TokenFontCache(familyName: initialEditor.fontFamily, size: CGFloat(initialEditor.fontSize))
        paragraphStyle = TabStopStyle.paragraphStyle(tabWidth: initialEditor.tabWidth, font: fontCache.baseFont)
        textView = MeridianTextView(usingTextLayoutManager: true)
        scrollView = NSScrollView()
        super.init()

        textView.isRichText = false
        textView.allowsUndo = false // UndoStack owns undo (spec decision 3)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = fontCache.baseFont
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView) { [weak self] in
            self?.buffer ?? TextBuffer()
        }
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        rulerView = ruler

        storage.delegate = self
        textView.delegate = self
        textView.onEffectiveAppearanceChange = { [weak self] in
            self?.handleAppearanceChange()
        }
        settingsStore.onChange { [weak self] settings in
            self?.applyEditorSettings(settings.editor)
        }
        applyEditorColors()
    }

    /// The TextKit 2 backing store. Trapping here is correct: a nil
    /// `textContentStorage` means the view silently downgraded to
    /// TextKit 1 — a programming error we must catch immediately.
    var storage: NSTextStorage {
        guard let contentStorage = textView.textContentStorage,
              let storage = contentStorage.textStorage
        else { preconditionFailure("NSTextView lost its TextKit 2 content storage") }
        return storage
    }

    var contentStorage: NSTextContentStorage {
        guard let contentStorage = textView.textContentStorage
        else { preconditionFailure("NSTextView lost its TextKit 2 content storage") }
        return contentStorage
    }

    public func load(buffer newBuffer: TextBuffer) {
        buffer = newBuffer
        loadGeneration += 1
        isMirroring = true
        defer { isMirroring = false }
        contentStorage.performEditingTransaction {
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length),
                with: newBuffer.string,
            )
            storage.setAttributes(
                typingAttributes, range: NSRange(location: 0, length: storage.length),
            )
        }
        highlightCurrentBuffer()
    }

    public func apply(_ transaction: EditTransaction, base: TextBuffer, restoreSelection: Bool) {
        precondition(
            base.version == buffer.version,
            "engine mirror out of sync with caller's base buffer",
        )
        isMirroring = true
        defer { isMirroring = false }
        contentStorage.performEditingTransaction {
            // Reverse order: each edit's range is relative to `base`;
            // applying back-to-front keeps earlier ranges valid.
            for edit in transaction.edits.reversed() {
                let location = base.utf16Offset(of: edit.range.lowerBound).value
                let length = base.utf16Offset(of: edit.range.upperBound).value - location
                storage.replaceCharacters(
                    in: NSRange(location: location, length: length),
                    with: edit.replacement.string,
                )
            }
        }
        buffer.apply(transaction)
        assertMirrorInvariant()
        highlightCurrentBuffer()
        if restoreSelection, !transaction.selectionAfter.ranges.isEmpty {
            setSelection(transaction.selectionAfter, in: buffer)
        }
    }

    public func selection(in buffer: TextBuffer) -> SelectionSet {
        let ranges = textView.selectedRanges.map(\.rangeValue).map { nsRange in
            let start = buffer.byteOffset(of: UTF16Offset(nsRange.location))
            let end = buffer.byteOffset(of: UTF16Offset(nsRange.location + nsRange.length))
            return start ..< end
        }
        return SelectionSet(ranges: ranges)
    }

    public func setSelection(_ selection: SelectionSet, in buffer: TextBuffer) {
        let nsRanges = selection.ranges.map { range in
            let location = buffer.utf16Offset(of: range.lowerBound).value
            let length = buffer.utf16Offset(of: range.upperBound).value - location
            return NSValue(range: NSRange(location: location, length: length))
        }
        guard !nsRanges.isEmpty else { return }
        textView.selectedRanges = nsRanges
    }

    public func scrollTo(_ offset: ByteOffset, in buffer: TextBuffer) {
        let location = buffer.utf16Offset(of: offset).value
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    public func setSoftWrap(_ enabled: Bool) {
        if enabled {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude,
            )
            scrollView.hasHorizontalScroller = true
        }
        textView.needsLayout = true
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
    }

    public func setGutterVisible(_ enabled: Bool) {
        scrollView.rulersVisible = enabled
    }

    /// Forces the TextKit 2 viewport to re-lay-out and redraw. Needed
    /// when a pane whose content was loaded while it had zero size (a
    /// freshly created split pane) is first shown at a real size:
    /// TextKit 2 lays out lazily for the visible viewport and does not
    /// render on that first non-zero sizing on its own, leaving the pane
    /// blank until some later relayout (e.g. a divider drag) nudges it.
    /// This reproduces that nudge deterministically.
    public func refreshViewportLayout() {
        scrollView.tile()
        textView.needsLayout = true
        textView.layoutSubtreeIfNeeded()
        if let tlm = textView.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
        }
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
    }

    private var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: fontCache.baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// Debug-only lockstep check (string materialization is O(n) — never
    /// ship this in a release hot path).
    private func assertMirrorInvariant() {
        assert(buffer.string == storage.string, "rope mirror desynced from NSTextStorage")
    }

    /// Converts an observed user-initiated storage change into an
    /// ``EditTransaction`` against the pre-edit snapshot, advances the
    /// snapshot, and reports it.
    private func handleUserEdit(newRange editedRange: NSRange, changeInLength delta: Int) {
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
        highlightCurrentBuffer()
        onUserEdit?(transaction)
    }
}

extension TextKit2Engine: NSTextViewDelegate {
    /// See `documentUndoManager`'s doc comment: this is what actually
    /// routes Cmd+Z/Cmd+Shift+Z to the host's undo manager instead of the
    /// text view's own (empty, since `allowsUndo = false`) one.
    public func undoManager(for view: NSTextView) -> UndoManager? {
        documentUndoManager
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        textView.needsDisplay = true
        rulerView?.needsDisplay = true
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

#if DEBUG
    extension TextKit2Engine {
        /// Test hooks — compiled out of release builds.
        var storageStringForTesting: String {
            storage.string
        }

        /// Reads a single storage attribute at a UTF-16 offset — used by
        /// bracket-match tests to confirm a `.backgroundColor` attribute
        /// is (or isn't) present at a specific location, without needing
        /// to know the exact `NSColor` value.
        func storageAttributeForTesting(_ key: NSAttributedString.Key, at utf16Offset: Int) -> Any? {
            guard utf16Offset < storage.length else { return nil }
            return storage.attribute(key, at: utf16Offset, effectiveRange: nil)
        }

        var snapshotStringForTesting: String {
            buffer.string
        }

        var snapshotForTesting: TextBuffer {
            buffer
        }

        /// Simulates user typing by mutating the storage directly, exactly as
        /// NSTextView's insertText path does (delegate fires → user-edit path).
        func simulateUserTypingForTesting(replacing range: NSRange, with string: String) {
            storage.replaceCharacters(in: range, with: string)
        }
    }
#endif
