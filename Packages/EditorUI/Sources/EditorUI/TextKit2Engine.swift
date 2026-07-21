import AppKit
import DocumentCore
import SyntaxKit

/// TextKit 2 conformer of ``TextLayoutEngine``: a standard `NSTextView`
/// backed by Apple's `NSTextContentStorage` (ADR 0009 verdict), with the
/// rope mirrored into `NSTextStorage`. The engine keeps its own
/// `TextBuffer` snapshot in lockstep with the storage so user edits can
/// be converted to rope coordinates against pre-edit content.
@MainActor
public final class TextKit2Engine: NSObject, TextLayoutEngine {
    private let scrollView: NSScrollView
    private let textView: MeridianTextView
    private var rulerView: LineNumberRulerView?
    /// The engine-local mirror snapshot. Invariant: equals the storage's
    /// string after every load/apply/user edit. Only ever touched from
    /// within `MainActor.assumeIsolated` (directly, or via the `@MainActor`
    /// methods below), so no `nonisolated(unsafe)` escape hatch is needed —
    /// see the delegate override's doc comment for the isolation bridge.
    private var buffer = TextBuffer()
    /// True while `load`/`apply` mutate the storage, so the delegate does
    /// not report our own mirroring as a user edit.
    private var isMirroring = false
    /// Increments every time `load(buffer:)` adopts a brand-new buffer
    /// lineage (never on `apply`, which reuses the same lineage). Needed
    /// because `TextBuffer.version` resets to 0 for every new `TextBuffer`
    /// instance, so two different lineages can share a version number —
    /// `highlightCurrentBuffer()`'s staleness check must distinguish
    /// "later edit of the same lineage" from "an entirely different
    /// lineage that happens to share a version" (e.g. `NSDocument` revert
    /// calling `load(buffer:)` again on the same engine).
    private var loadGeneration = 0

    private let syntaxService = SyntaxService()
    private let syntaxDocumentID = DocumentID()
    /// Detected once at `load(buffer:)` time from the document's file
    /// extension (set externally — see `languageID(forFileExtension:)`
    /// below); `nil` means "don't highlight" (any extension besides
    /// json/swift, or no extension known yet).
    public var languageID: String?

    /// Temporary hardcoded palette (design spec Decision 5) — replaced
    /// wholesale by real `ThemeKit` resolution in a later M4 phase. Do
    /// not extend this table; it exists only to prove the pipeline
    /// paints real color end-to-end.
    private static let temporaryColors: [TokenType: NSColor] = [
        .keyword: .systemPurple,
        .string: .systemGreen,
        .comment: .systemGray,
        .function: .systemBlue,
        .type: .systemTeal,
        .variable: .textColor,
        .property: .systemBlue,
        .number: .systemOrange,
        .constant: .systemOrange,
        .punctuation: .textColor,
        .plain: .textColor,
    ]

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

    /// Builds the scroll view + TextKit 2 text view, plain-text config.
    override public init() {
        textView = MeridianTextView(usingTextLayoutManager: true)
        scrollView = NSScrollView()
        super.init()

        textView.isRichText = false
        textView.allowsUndo = false // UndoStack owns undo (spec decision 3)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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
    }

    /// The TextKit 2 backing store. Trapping here is correct: a nil
    /// `textContentStorage` means the view silently downgraded to
    /// TextKit 1 — a programming error we must catch immediately.
    private var storage: NSTextStorage {
        guard let contentStorage = textView.textContentStorage,
              let storage = contentStorage.textStorage
        else { preconditionFailure("NSTextView lost its TextKit 2 content storage") }
        return storage
    }

    private var contentStorage: NSTextContentStorage {
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

    /// Kicks off a background reparse + repaint for the current buffer.
    /// Fire-and-forget: discards the result if `buffer.version` has
    /// already moved on by the time the actor call returns (stale-result
    /// drop, ARCHITECTURE §3.4), or if `loadGeneration` has advanced —
    /// i.e. `load(buffer:)` adopted an entirely different buffer lineage
    /// in the meantime (e.g. an `NSDocument` revert), which could
    /// otherwise share the stale request's version number by coincidence
    /// since `TextBuffer.version` resets to 0 on every new instance.
    private func highlightCurrentBuffer() {
        guard let languageID else { return }
        let snapshot = buffer
        let requestedVersion = snapshot.version
        let requestedGeneration = loadGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let runs: [TokenRun]
            do {
                runs = try await syntaxService.reparse(
                    documentID: syntaxDocumentID,
                    languageID: languageID,
                    snapshot: snapshot,
                    version: requestedVersion,
                    edit: nil,
                )
            } catch {
                return
            }
            guard loadGeneration == requestedGeneration,
                  buffer.version == requestedVersion
            else { return }
            applyHighlighting(runs, against: snapshot)
        }
    }

    private func applyHighlighting(_ runs: [TokenRun], against snapshot: TextBuffer) {
        isMirroring = true
        defer { isMirroring = false }
        contentStorage.performEditingTransaction {
            for run in runs {
                let color = Self.temporaryColors[run.type] ?? .textColor
                let location = snapshot.utf16Offset(of: run.range.lowerBound).value
                let length = snapshot.utf16Offset(of: run.range.upperBound).value - location
                guard location >= 0, length >= 0, location + length <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: length))
            }
        }
    }

    public func apply(_ transaction: EditTransaction, base: TextBuffer) {
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
        if !transaction.selectionAfter.ranges.isEmpty {
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

    private var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
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
