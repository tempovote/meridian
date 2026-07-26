// swiftlint:disable file_length
import AppKit
import DocumentCore
import FileKit
import SettingsKit
import SyntaxKit
import ThemeKit

/// TextKit 2 conformer of ``TextLayoutEngine``: a standard `NSTextView`
/// backed by Apple's `NSTextContentStorage` (ADR 0009 verdict), with the
/// rope mirrored into `NSTextStorage`. The engine keeps its own
/// `TextBuffer` snapshot in lockstep with the storage so user edits can
/// be converted to rope coordinates against pre-edit content.
@MainActor
// swiftlint:disable:next type_body_length
public final class TextKit2Engine: NSObject, TextLayoutEngine {
    private let scrollView: NSScrollView
    let textView: MeridianTextView
    /// Internal, not private: fold-only relayout needs to invalidate the
    /// ruler too, without going through `refreshViewportLayout()`.
    var rulerView: LineNumberRulerView?
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
    /// UTF-16 spans of the lines currently hidden by folding, sorted,
    /// derived by `setHiddenLineSpans(_:)`. Read by the layout-manager
    /// delegate on every fragment creation — keep sorted for binary search.
    var hiddenUTF16Spans: [Range<Int>] = []
    /// UTF-16 offset of each folded region's still-visible first line ->
    /// that region's byte-range lower bound (the key `FoldModel.unfold
    /// (startingAt:)` expects). Updated alongside `hiddenUTF16Spans`; lets
    /// the `…` placeholder fragment and its click-to-unfold hit test
    /// answer "am I/is this a folded first line?" in O(1) without walking
    /// `foldModel.folded`.
    var foldedFirstLineUTF16Starts: [Int: ByteOffset] = [:]
    /// This pane's fold state, fed by every successful parse
    /// (`highlightCurrentBuffer`) and mutated by the fold operations in
    /// `TextKit2Engine+Folding.swift`.
    var foldModel = FoldModel()
    /// True while a `refreshFoldLayoutDeferred()` relayout hop is already
    /// scheduled — coalesces a burst of real-typing edits (each of which
    /// calls `refreshFoldLayoutDeferred()` from `handleUserEdit`) down to
    /// one deferred `relayoutForFoldChange()` call. See that method's doc
    /// comment.
    var hasPendingDeferredFoldRelayout = false
    /// The most recently scheduled deferred fold relayout `Task`, kept
    /// only so the DEBUG-only `waitForDeferredFoldRelayoutForTesting` hook
    /// can await it deterministically instead of sleeping in tests.
    var deferredFoldRelayoutTask: Task<Void, Never>?
    /// The most recent parse `Task` kicked off by `highlightCurrentBuffer`,
    /// kept only so the DEBUG-only `waitForParseForTesting` hook can await
    /// its completion deterministically instead of sleeping in tests.
    var lastParseTask: Task<Void, Never>?
    #if DEBUG
        /// Test-only: counts `relayoutForFoldChange()` calls — asserts the
        /// relayout/purge path was skipped when nothing fold-related changed.
        var foldRelayoutInvocationCountForTesting = 0
    #endif

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

    /// Called whenever the editor is scrolled with the first visible and last
    /// visible 1-based line numbers. Used to sync the Minimap viewport rect.
    public var onScrollChange: ((ClosedRange<Int>) -> Void)?

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
        configureFoldGutter()
        textView.delegate = self
        textView.textLayoutManager?.delegate = self
        textView.onEffectiveAppearanceChange = { [weak self] in
            self?.handleAppearanceChange()
        }
        textView.onOptionClick = { [weak self] point in
            self?.handleOptionClick(at: point)
        }
        textView.onAddCaretAbove = { [weak self] in
            self?.handleAddCaretAbove()
        }
        textView.onAddCaretBelow = { [weak self] in
            self?.handleAddCaretBelow()
        }
        settingsStore.onChange { [weak self] settings in
            self?.applyEditorSettings(settings.editor)
        }
        applyEditorColors()
        setupScrollObserver()
    }

    /// Sets up an NSScrollView bounds-change observer for Minimap scroll sync.
    /// Called separately to keep init body under the SwiftLint line limit.
    func setupScrollObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    @objc public func handleScrollBoundsChange() {
        let visibleRect = scrollView.contentView.documentVisibleRect
        guard visibleRect.height > 0 else { return }

        var firstLine = 1
        var lastLine = 1

        if let mgr = textView.textLayoutManager {
            let docRange = mgr.documentRange
            let startPt = CGPoint(x: 4, y: visibleRect.minY + 2)
            let endPt = CGPoint(x: 4, y: max(visibleRect.minY + 2, visibleRect.maxY - 2))

            let startFrag = mgr.textLayoutFragment(for: startPt)
            if let startLoc = startFrag?.rangeInElement.location {
                let offset = mgr.offset(from: docRange.location, to: startLoc)
                firstLine = buffer.linePosition(of: UTF16Offset(offset)).line + 1
            } else {
                let ratio = visibleRect.minY / max(1, textView.bounds.height)
                firstLine = max(1, Int(ratio * CGFloat(max(1, buffer.lineCount))))
            }

            let endFrag = mgr.textLayoutFragment(for: endPt)
            if let endLoc = endFrag?.rangeInElement.location {
                let offset = mgr.offset(from: docRange.location, to: endLoc)
                lastLine = buffer.linePosition(of: UTF16Offset(offset)).line + 1
            } else {
                let ratio = visibleRect.maxY / max(1, textView.bounds.height)
                lastLine = max(firstLine, Int(ratio * CGFloat(max(1, buffer.lineCount))))
            }
        } else {
            let lineHeight = textView.font.map { $0.ascender - $0.descender + $0.leading } ?? 14
            let effectiveLineHeight = max(1, lineHeight + 2)
            firstLine = max(1, Int(visibleRect.minY / effectiveLineHeight) + 1)
            lastLine = max(firstLine, Int(visibleRect.maxY / effectiveLineHeight) + 1)
        }

        onScrollChange?(firstLine ... max(firstLine, lastLine))
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
        // Reset fold state: a revert/reload otherwise leaves stale hidden
        // spans hiding lines of the new content (see `loadGeneration` doc).
        foldModel = FoldModel()
        hiddenUTF16Spans = []
        foldedFirstLineUTF16Starts = [:]
        hasPendingDeferredFoldRelayout = false
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
                let repString = edit.replacement.string
                storage.replaceCharacters(
                    in: NSRange(location: location, length: length),
                    with: repString,
                )
                let repLength = edit.replacement.utf16Count
                if repLength > 0, location + repLength <= storage.length {
                    storage.setAttributes(
                        typingAttributes,
                        range: NSRange(location: location, length: repLength),
                    )
                }
            }
        }
        buffer.apply(transaction)
        assertMirrorInvariant()
        let foldedBefore = foldModel.folded
        foldModel.apply(transaction)
        if foldModel.folded != foldedBefore {
            refreshFoldLayout()
        }
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
        let maxByte = buffer.utf8Count
        let maxUtf16 = buffer.utf16Count
        let nsRanges = selection.ranges.compactMap { range -> NSValue? in
            let lowerByte = min(range.lowerBound.value, maxByte)
            let upperByte = min(range.upperBound.value, maxByte)
            let location = buffer.utf16Offset(of: ByteOffset(lowerByte)).value
            let length = buffer.utf16Offset(of: ByteOffset(upperByte)).value - location
            guard location <= maxUtf16, (location + length) <= maxUtf16 else { return nil }
            return NSValue(range: NSRange(location: location, length: length))
        }
        guard !nsRanges.isEmpty else { return }
        if nsRanges.count > 1 {
            textView.applyMultiCaretRanges(nsRanges)
        } else {
            textView.setSelectedRange(nsRanges[0].rangeValue)
        }
        updateTextLayoutManagerSelections(from: nsRanges)
        textView.needsDisplay = true
    }

    private func updateTextLayoutManagerSelections(from nsRanges: [NSValue]) {
        guard let textLayoutManager = textView.textLayoutManager,
              let docStart = textLayoutManager.documentRange.location as NSTextLocation?
        else { return }

        let textSelections = nsRanges.compactMap { val -> NSTextSelection? in
            let nsRange = val.rangeValue
            guard let startLoc = textLayoutManager.location(docStart, offsetBy: nsRange.location),
                  let endLoc = textLayoutManager.location(startLoc, offsetBy: nsRange.length),
                  let textRange = NSTextRange(location: startLoc, end: endLoc)
            else { return nil }
            return NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)
        }

        if !textSelections.isEmpty {
            textLayoutManager.textSelections = textSelections
        }
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

    public func setGitGutterMarkProvider(_ provider: ((Int) -> GitGutterMark)?) {
        rulerView?.gitGutterMarkProvider = provider
        rulerView?.needsDisplay = true
    }

    /// Debug-only lockstep check (string materialization is O(n) — never
    /// ship this in a release hot path).
    func assertMirrorInvariant() {
        assert(buffer.string == storage.string, "rope mirror desynced from NSTextStorage")
    }
}
