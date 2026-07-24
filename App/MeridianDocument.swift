// swiftlint:disable file_length
import AppKit
import DocumentCore
import EditorUI
import FileKit
import SwiftUI
import ThemeKit
import WorkspaceUI

/// Errors that block opening a document, with user-facing text.
enum DocumentOpenError: LocalizedError {
    /// File exceeds the huge-file threshold (bytes given).
    case tooLarge(byteSize: Int)
    /// A single line exceeds the pathological-line threshold (ADR 0009:
    /// a 100 MB single-line file drives TextKit RSS to 11 GB).
    case lineTooLong(utf8Length: Int)

    var errorDescription: String? {
        switch self {
        case let .tooLarge(byteSize):
            "This file is \(byteSize / (1024 * 1024)) MB. Files of 64 MB or more need "
                + "huge-file mode, which arrives in a later release."
        case .lineTooLong:
            "This file contains an extremely long line, which this version cannot "
                + "display safely. Support arrives with huge-file mode in a later release."
        }
    }
}

/// The two ways a document's editor can be split into two panes. Naming
/// matches the View-menu items, NOT `NSSplitView.isVertical` (whose
/// "vertical" describes the DIVIDER's orientation, the opposite of the
/// pane-arrangement naming used here and in the menu — `.horizontal`
/// (stacked panes, divider runs horizontally) sets `isVertical = false`;
/// `.vertical` (side-by-side panes, divider runs vertically) sets
/// `isVertical = true`).
private enum SplitOrientation {
    case horizontal
    case vertical
}

/// `.thin`'s default 1pt divider is difficult to click-and-drag precisely
/// — double the hit/visual width so grabbing it is comfortable, matching
/// user feedback during feel-check.
///
/// Also seeds an even 50/50 divider position exactly once, on the first
/// layout pass at which it has a real (non-zero) size. `NSSplitView`
/// otherwise distributes space proportionally to the panes' existing
/// frames, and a brand-new pane starts at frame zero, so the
/// pre-existing pane keeps everything. Doing this from `layout()` AFTER
/// `super.layout()` (which runs `adjustSubviews` and gives the split
/// view a real size) means `setPosition` only ever moves the divider,
/// never resizes the split view itself. After the one-time seed it never
/// touches positioning again, so it doesn't fight the user dragging the
/// divider or a later window resize.
private final class WideDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        super.dividerThickness * 2
    }

    private var hasSeededInitialPosition = false

    /// Invoked once, immediately after the first layout pass has given
    /// the panes real frames and the 50/50 split has been seeded — the
    /// point at which a fresh pane's engine can finally render its
    /// viewport against a real size (see `refreshViewportLayout`).
    var onInitialLayout: (() -> Void)?

    override func layout() {
        super.layout()
        guard !hasSeededInitialPosition,
              subviews.count > 1,
              bounds.width > 0, bounds.height > 0
        else { return }
        hasSeededInitialPosition = true
        onInitialLayout?()
    }
}

/// The NSDocument bridge: FileKit I/O on the outside, a `DocumentModel`
/// (shared buffer/undo) plus one or two `EditorViewModel` panes (each its
/// own engine + display settings) as the authoritative model, thin
/// NSUndoManager actions replaying the rope's UndoStack (spec decision 3).
final class MeridianDocument: NSDocument {
    // swiftlint:disable:previous type_body_length
    /// Huge-file threshold: at or above this size, refuse to open.
    nonisolated static let maxFileSize = 64 * 1024 * 1024
    /// Pathological-line threshold, in UTF-8 bytes.
    nonisolated static let maxLineLength = 1_000_000

    private var documentModel: DocumentModel?
    /// One entry when unsplit, two when split. Index 0 is always the
    /// original/primary pane; index 1 (when present) is the secondary
    /// pane created by a split.
    private var panes: [(viewModel: EditorViewModel, engine: TextKit2Engine)] = []
    private var currentSplitOrientation: SplitOrientation?
    /// Which `panes` index the window's first responder currently belongs
    /// to — drives which pane View-menu toggles/text-transform commands
    /// act on, and which pane's state the status bar shows.
    private var focusedPaneIndex: Int = 0
    private var statusBarHost: NSHostingView<StatusBarView>?
    /// Whatever currently occupies the container stack's editor/split slot
    /// (a single pane's `engine.view`, or an `NSSplitView` wrapping two) —
    /// tracked explicitly rather than assumed to be
    /// `containerStack.arrangedSubviews.first`, because the find bar and
    /// command palette ALSO insert themselves at index 0 (`.top` gravity
    /// renders above the editor) while open. Without this, splitting while
    /// either overlay is open would remove and orphan the overlay's host
    /// instead of the editor slot.
    private var editorSlotView: NSView?
    /// Metadata from the loaded file (encoding/BOM for faithful save);
    /// nil for untitled documents (saved as UTF-8, no BOM, LF).
    private var loadedMetadata: (encoding: TextEncoding, hadBOM: Bool)?
    /// Buffer read before window controllers exist.
    private var pendingBuffer = TextBuffer()

    private var focusedViewModel: EditorViewModel? {
        panes.indices.contains(focusedPaneIndex) ? panes[focusedPaneIndex].viewModel : nil
    }

    private var focusedEngine: TextKit2Engine? {
        panes.indices.contains(focusedPaneIndex) ? panes[focusedPaneIndex].engine : nil
    }

    // swiftlint:disable:next static_over_final_class
    override class var autosavesInPlace: Bool {
        false
    }

    override func read(from url: URL, ofType typeName: String) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard size < Self.maxFileSize else {
            throw DocumentOpenError.tooLarge(byteSize: size)
        }
        let file = try TextFileIO.loadTextFile(at: url)
        guard file.longestLineUTF8Length < Self.maxLineLength else {
            throw DocumentOpenError.lineTooLong(utf8Length: file.longestLineUTF8Length)
        }
        MainActor.assumeIsolated {
            loadedMetadata = (file.encoding, file.hadBOM)
            pendingBuffer = file.buffer
            // Re-opened into an existing window (revert): reload the
            // model. Rebuild rather than diff — P1 has no revert UI; this
            // path only runs for NSDocument's built-in revert. Revert
            // always collapses back to a single pane — tear down a
            // dropped secondary pane the same way removeSplit() does, so
            // its callbacks don't fire against stale state and first
            // responder doesn't end up pointing at a view no longer in
            // the hierarchy.
            guard !panes.isEmpty else { return }
            if panes.count > 1 {
                detachSecondaryPane(panes[1])
            }
            // The primary pane's `EditorViewModel` is also about to be
            // replaced below (`newViewModel`) — drop a Find bar view
            // model bound to it the same way `detachSecondaryPane` does
            // for the secondary pane, so it doesn't linger as a dangling
            // search target.
            if let findBarViewModel, findBarViewModel.isBound(to: panes[0].viewModel) {
                self.findBarViewModel = nil
            }
            let newDocumentModel = DocumentModel(buffer: file.buffer)
            documentModel = newDocumentModel
            let primaryEngine = panes[0].engine
            primaryEngine.languageID = languageID(forFileExtension: url.pathExtension)
            let newViewModel = EditorViewModel(documentModel: newDocumentModel, engine: primaryEngine)
            newViewModel.isSoftWrapEnabled = AppDelegate.settingsStore.current.editor.softWrapDefault
            panes = [(newViewModel, primaryEngine)]
            currentSplitOrientation = nil
            focusedPaneIndex = 0
            wireUndoCallback()
            wireMirroring()
            wireFocusTracking()
            rebuildSplitLayout()
            windowControllers.first?.window?.makeFirstResponder(panes[0].engine.keyView)
            refreshStatusBar()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let buffer = MainActor.assumeIsolated { documentModel?.buffer } ?? pendingBuffer
        let metadata = loadedMetadata ?? (.utf8, false)
        return try TextFileIO.encode(buffer, as: metadata.encoding, includeBOM: metadata.hadBOM)
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            let documentModel = DocumentModel(buffer: pendingBuffer)
            self.documentModel = documentModel
            let engine = makeEngine(languageID: fileURL.flatMap { languageID(forFileExtension: $0.pathExtension) })
            let viewModel = EditorViewModel(documentModel: documentModel, engine: engine)
            viewModel.isSoftWrapEnabled = AppDelegate.settingsStore.current.editor.softWrapDefault
            panes = [(viewModel, engine)]
            wireUndoCallback()
            wireMirroring()
            wireFocusTracking()

            let encodingName = loadedMetadata?.encoding.displayName ?? "UTF-8"
            let statusBar = StatusBarView(
                viewModel: viewModel,
                encodingName: encodingName,
                lineEndingName: "LF",
            )
            let host = NSHostingView(rootView: statusBar)
            statusBarHost = host

            let containerStack = NSStackView(views: [engine.view, host])
            containerStack.orientation = .vertical
            containerStack.spacing = 0
            containerStack.alignment = .width
            editorSlotView = engine.view
            host.setContentHuggingPriority(.required, for: .vertical)

            NSWindow.allowsAutomaticWindowTabbing = true
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false,
            )
            window.tabbingMode = .preferred
            window.center()
            window.contentView = containerStack
            window.makeFirstResponder(engine.keyView)
            addWindowController(NSWindowController(window: window))
        }
    }

    /// Builds a new `TextKit2Engine` wired to this document's undo manager.
    /// `languageID` is only supplied for the primary pane (detected from
    /// the file extension); a secondary pane created by a split copies its
    /// language from the pane it was split from (see `setSplit`).
    private func makeEngine(languageID: String?) -> TextKit2Engine {
        let engine = TextKit2Engine(themeEngine: AppDelegate.themeEngine, settingsStore: AppDelegate.settingsStore)
        engine.languageID = languageID
        engine.documentUndoManager = undoManager
        return engine
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        focusedViewModel?.isGutterVisible.toggle()
    }

    @objc func toggleSoftWrap(_ sender: Any?) {
        focusedViewModel?.isSoftWrapEnabled.toggle()
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.isStatusBarVisible.toggle()
        statusBarHost?.isHidden = !viewModel.isStatusBarVisible
    }

    @objc func splitHorizontally(_ sender: Any?) {
        setSplit(orientation: .horizontal)
    }

    @objc func splitVertically(_ sender: Any?) {
        setSplit(orientation: .vertical)
    }

    @objc func foldCurrentRegion(_ sender: Any?) {
        focusedViewModel?.foldAtCaret()
    }

    @objc func unfoldCurrentRegion(_ sender: Any?) {
        focusedViewModel?.unfoldAtCaret()
    }

    @objc func foldAll(_ sender: Any?) {
        focusedViewModel?.foldAll()
    }

    @objc func unfoldAll(_ sender: Any?) {
        focusedViewModel?.unfoldAll()
    }

    @objc func foldLevel1(_ sender: Any?) {
        focusedViewModel?.foldLevel(1)
    }

    @objc func foldLevel2(_ sender: Any?) {
        focusedViewModel?.foldLevel(2)
    }

    @objc func foldLevel3(_ sender: Any?) {
        focusedViewModel?.foldLevel(3)
    }

    @objc func foldLevel4(_ sender: Any?) {
        focusedViewModel?.foldLevel(4)
    }

    @objc func foldLevel5(_ sender: Any?) {
        focusedViewModel?.foldLevel(5)
    }

    /// Choosing the already-active orientation removes the split;
    /// choosing the other orientation while split re-orients in place;
    /// choosing either while unsplit creates the second pane.
    private func setSplit(orientation: SplitOrientation) {
        guard let documentModel, let primary = panes.first else { return }
        if currentSplitOrientation == orientation {
            removeSplit()
            return
        }
        if panes.count == 1 {
            let secondaryEngine = makeEngine(languageID: primary.engine.languageID)
            let secondaryViewModel = EditorViewModel(documentModel: documentModel, engine: secondaryEngine)
            secondaryViewModel.isGutterVisible = primary.viewModel.isGutterVisible
            secondaryViewModel.isSoftWrapEnabled = primary.viewModel.isSoftWrapEnabled
            secondaryViewModel.isCurrentLineHighlightEnabled = primary.viewModel.isCurrentLineHighlightEnabled
            secondaryViewModel.isStatusBarVisible = primary.viewModel.isStatusBarVisible
            panes.append((secondaryViewModel, secondaryEngine))
            wireMirroring()
            wireFocusTracking()
        }
        currentSplitOrientation = orientation
        rebuildSplitLayout()
    }

    /// Tears down a pane's callbacks so it doesn't fire against stale
    /// state after being dropped from `panes` — shared by `removeSplit()`
    /// and revert's pane-collapse path in `read(from:ofType:)`. Also
    /// drops `findBarViewModel` if it was searching this pane: since
    /// closing the Find bar no longer clears it (so ⌘G/⇧⌘G keep working
    /// with the bar closed — see `FindBarViewModel`'s doc comment), a
    /// dropped pane's view model would otherwise linger as a dangling
    /// search target that ⌘G silently no-ops against until Find is
    /// reopened on a still-live pane.
    private func detachSecondaryPane(_ pane: (viewModel: EditorViewModel, engine: TextKit2Engine)) {
        pane.viewModel.onDidApplyTransaction = nil
        pane.engine.onBecomeFirstResponder = nil
        if let findBarViewModel, findBarViewModel.isBound(to: pane.viewModel) {
            self.findBarViewModel = nil
        }
    }

    private func removeSplit() {
        guard panes.count > 1 else { return }
        let removed = panes.removeLast()
        detachSecondaryPane(removed)
        currentSplitOrientation = nil
        focusedPaneIndex = 0
        rebuildSplitLayout()
        windowControllers.first?.window?.makeFirstResponder(panes[0].engine.keyView)
        refreshStatusBar()
    }

    /// Swaps whatever currently occupies the container stack's top slot
    /// (a single pane's view, or a previous split view) for the correct
    /// view given `panes.count` and `currentSplitOrientation`.
    private func rebuildSplitLayout() {
        guard let window = windowControllers.first?.window,
              let containerStack = window.contentView as? NSStackView
        else { return }
        // Remove the tracked editor slot specifically — NOT
        // `arrangedSubviews.first`, which the find bar / command palette
        // can also occupy (see `editorSlotView`'s doc comment).
        if let existingPrimarySlot = editorSlotView {
            containerStack.removeArrangedSubview(existingPrimarySlot)
            existingPrimarySlot.removeFromSuperview()
        }
        let newPrimarySlot: NSView
        if let orientation = currentSplitOrientation, panes.count > 1 {
            let splitView = WideDividerSplitView()
            // See `SplitOrientation`'s doc comment for why this looks
            // inverted: `.vertical` (side-by-side panes) needs a VERTICAL
            // divider, i.e. `isVertical = true`.
            splitView.isVertical = orientation == .vertical
            splitView.dividerStyle = .thin
            // Give the freshly created secondary pane the SAME frame as the
            // established primary pane before adding either to the split
            // view. This is the crux of getting an even split: `NSSplitView`
            // sizes its subviews by `adjustSubviews`, which scales them
            // *proportionally to their current frames* to fill the split
            // view. A brand-new pane starts at frame zero, so with unequal
            // starting frames the proportion is 1:0 — the new pane gets
            // nothing (and, for a horizontal/stacked split, is even treated
            // as collapsed and can't be recovered by `setPosition`). Seeding
            // both panes to the same non-zero frame makes the proportion
            // 1:1, i.e. a clean 50/50, with neither pane collapsed.
            let seedFrame = panes[0].engine.view.frame
            for pane in panes {
                // Classic frame-managed split panes: `NSSplitView` sizes
                // these directly via `adjustSubviews`, which requires
                // autoresizing rather than Auto Layout. (When a pane returns
                // to the single-pane slot, the host `NSStackView` flips this
                // back to `false` for its own Auto Layout.)
                pane.engine.view.translatesAutoresizingMaskIntoConstraints = true
                pane.engine.view.frame = seedFrame
                splitView.addSubview(pane.engine.view)
            }
            // Once the first layout pass has sized the panes, force each
            // engine to render its viewport — a freshly created pane loaded
            // its content while sized zero, and TextKit 2 won't render on
            // the first sizing on its own (see `refreshViewportLayout`).
            // This must fire AFTER that layout pass, so it hangs off the
            // split view's post-layout callback rather than running here.
            splitView.onInitialLayout = { [weak self] in
                guard let self else { return }
                for pane in panes {
                    pane.engine.refreshViewportLayout()
                }
            }
            newPrimarySlot = splitView
        } else {
            newPrimarySlot = panes[0].engine.view
        }
        newPrimarySlot.setContentHuggingPriority(.defaultLow, for: .vertical)
        // Insert below any open overlay (find bar / command palette), not
        // unconditionally at index 0 — an open overlay currently occupies
        // that slot and must stay on top of the editor, not be displaced.
        let overlayIsOpen = findBarHost != nil || commandPaletteHost != nil
        let insertIndex = overlayIsOpen ? 1 : 0
        containerStack.insertView(newPrimarySlot, at: insertIndex, in: .top)
        editorSlotView = newPrimarySlot
    }

    /// Wires every pane's `onDidApplyTransaction` to mirror into every
    /// OTHER pane's engine, content-only (no selection change there).
    /// Safe to call repeatedly (e.g. after adding/removing a pane) — it
    /// just reassigns each pane's callback to the current `panes` array.
    private func wireMirroring() {
        for (index, pane) in panes.enumerated() {
            pane.viewModel.onDidApplyTransaction = { [weak self] transaction, base in
                guard let self else { return }
                for (otherIndex, other) in panes.enumerated() where otherIndex != index {
                    other.engine.apply(transaction, base: base, restoreSelection: false)
                }
            }
        }
    }

    /// Wires every pane's engine to update `focusedPaneIndex` and the
    /// status bar when that pane's text view becomes first responder.
    private func wireFocusTracking() {
        for (index, pane) in panes.enumerated() {
            pane.engine.onBecomeFirstResponder = { [weak self] in
                self?.focusedPaneIndex = index
                self?.refreshStatusBar()
            }
        }
    }

    private func refreshStatusBar() {
        guard let host = statusBarHost, let viewModel = focusedViewModel else { return }
        let encodingName = loadedMetadata?.encoding.displayName ?? "UTF-8"
        host.rootView = StatusBarView(
            viewModel: viewModel,
            encodingName: encodingName,
            lineEndingName: "LF",
        )
        // Reconcile visibility with the newly-focused pane's own toggle —
        // without this, hiding the bar while pane A is focused then
        // switching focus to pane B (whose isStatusBarVisible is still
        // true) would leave the bar hidden despite the View-menu checkmark
        // (which reads focusedViewModel.isStatusBarVisible) showing "on".
        host.isHidden = !viewModel.isStatusBarVisible
    }

    private var findBarHost: NSHostingView<FindBarView>?
    /// Owns Find & Replace's search/navigation state — see
    /// `FindBarViewModel`'s doc comment for why this lives here rather
    /// than as `FindBarView`'s private `@State`.
    private var findBarViewModel: FindBarViewModel?

    @objc func performFind(_ sender: Any?) {
        showFindBar(startExpanded: false)
    }

    @objc func performFindAndReplace(_ sender: Any?) {
        showFindBar(startExpanded: true)
    }

    @objc func findNext(_ sender: Any?) {
        findBarViewModel?.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        findBarViewModel?.findPrevious()
    }

    private var commandPaletteHost: NSHostingView<CommandPaletteView>?
    /// Local mouse-down monitor that dismisses the palette on click-outside
    /// (spec: "The palette closes on Esc, on executing a command, or on
    /// click-outside"). Installed only while the palette is open; removed
    /// in `hideCommandPalette()` so it never lingers over normal editing.
    private var commandPaletteClickMonitor: Any?

    @objc func showCommandPalette(_ sender: Any?) {
        guard commandPaletteHost == nil else {
            hideCommandPalette()
            return
        }
        let viewModel = CommandPaletteViewModel(commands: CommandRegistry.commands)
        let paletteView = CommandPaletteView(
            viewModel: viewModel,
            onExecute: { [weak self] in
                guard let self, let command = viewModel.selectedCommand else { return }
                hideCommandPalette()
                // Commands `MeridianDocument` implements directly (the toggles
                // and text transforms — see the list in `CommandRegistry`'s
                // Edit/View sections) are sent straight to `self`, bypassing
                // the responder-chain walk entirely. That walk depends on
                // `hideCommandPalette()` having already handed first-responder
                // status back to the editor's text view — true today, but a
                // needless dependency for actions `self` already answers to
                // directly, and one that showed up here as "Soft Wrap doesn't
                // actually toggle" when invoked from the palette. Commands the
                // document does NOT implement (Cut/Copy/Paste/Select All,
                // which `NSTextView` answers; Undo/Redo, which it also
                // intercepts itself — see `documentUndoManager`'s doc comment)
                // still need the real responder-chain resolution, since only
                // the text view (now first responder again) can answer them.
                if responds(to: command.selector) {
                    NSApp.sendAction(command.selector, to: self, from: nil)
                } else {
                    NSApp.sendAction(command.selector, to: nil, from: nil)
                }
            },
            onClose: { [weak self] in
                self?.hideCommandPalette()
            },
        )
        let host = NSHostingView(rootView: paletteView)
        commandPaletteHost = host
        if let window = windowControllers.first?.window, let containerStack = window.contentView as? NSStackView {
            containerStack.insertView(host, at: 0, in: .top)
            window.makeFirstResponder(host)
            commandPaletteClickMonitor = NSEvent
                .addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self else { return event }
                    // Only clicks inside this document's own window can dismiss
                    // its palette — other windows (e.g. another document) are
                    // left alone.
                    guard event.window === window else { return event }
                    let locationInHost = host.convert(event.locationInWindow, from: nil)
                    if !host.bounds.contains(locationInHost) {
                        hideCommandPalette()
                    }
                    return event
                }
        }
    }

    private func hideCommandPalette() {
        if let monitor = commandPaletteClickMonitor {
            NSEvent.removeMonitor(monitor)
            commandPaletteClickMonitor = nil
        }
        if let host = commandPaletteHost {
            host.removeFromSuperview()
            commandPaletteHost = nil
            windowControllers.first?.window?.makeFirstResponder(focusedEngine?.keyView)
        }
    }

    @objc func duplicateLine(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.duplicateLines(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func deleteLine(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.deleteLines(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func trimTrailingWhitespace(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.trimTrailingWhitespace(in: viewModel.buffer))
    }

    @objc func makeUpperCase(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel
            .perform(TextTransforms
                .transformCase(in: viewModel.buffer, selection: viewModel.selection) { $0.uppercased() })
    }

    @objc func makeLowerCase(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel
            .perform(TextTransforms
                .transformCase(in: viewModel.buffer, selection: viewModel.selection) { $0.lowercased() })
    }

    @objc func convertLineEndingsToLF(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.convertLineEndings(in: viewModel.buffer, to: .lf))
    }

    @objc func convertLineEndingsToCRLF(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.convertLineEndings(in: viewModel.buffer, to: .crlf))
    }

    private func showFindBar(startExpanded: Bool) {
        guard let viewModel = focusedViewModel, findBarHost == nil else { return }
        // Reuse the existing search state (query/matches/current index) if
        // it's still for the same pane — closing the Find bar only hides
        // its UI, it doesn't discard the search, so ⌘G/⇧⌘G keep working
        // while it's closed and reopening resumes where the user left off.
        // A stale instance (e.g. focus moved to a different split pane
        // since the bar was last open) is replaced with a fresh one.
        let findBarVM: FindBarViewModel = if let existing = findBarViewModel, existing.isBound(to: viewModel) {
            existing
        } else {
            FindBarViewModel(editorViewModel: viewModel, startExpanded: startExpanded)
        }
        if startExpanded {
            findBarVM.isReplaceExpanded = true
        }
        findBarViewModel = findBarVM
        let findView = FindBarView(viewModel: findBarVM) { [weak self] in
            self?.hideFindBar()
        }
        let host = NSHostingView(rootView: findView)
        findBarHost = host

        if let window = windowControllers.first?.window, let containerStack = window.contentView as? NSStackView {
            containerStack.insertView(host, at: 0, in: .top)
            window.makeFirstResponder(host)
        }
    }

    private func hideFindBar() {
        if let host = findBarHost {
            host.removeFromSuperview()
            findBarHost = nil
            windowControllers.first?.window?.makeFirstResponder(focusedEngine?.keyView)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !(findBarViewModel?.matches.isEmpty ?? true)
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = (focusedViewModel?.isGutterVisible == true) ? .on : .off
            return true
        case #selector(toggleSoftWrap(_:)):
            menuItem.state = (focusedViewModel?.isSoftWrapEnabled == true) ? .on : .off
            return true
        case #selector(toggleStatusBar(_:)):
            menuItem.state = (focusedViewModel?.isStatusBarVisible == true) ? .on : .off
            return true
        case #selector(splitHorizontally(_:)):
            menuItem.state = (currentSplitOrientation == .horizontal) ? .on : .off
            return true
        case #selector(splitVertically(_:)):
            menuItem.state = (currentSplitOrientation == .vertical) ? .on : .off
            return true
        case #selector(foldCurrentRegion(_:)):
            return focusedViewModel?.canFoldAtCaret == true
        case #selector(unfoldCurrentRegion(_:)):
            return focusedViewModel?.canUnfoldAtCaret == true
        case #selector(foldAll(_:)):
            return focusedViewModel?.canFoldAll == true
        case #selector(unfoldAll(_:)):
            return focusedViewModel?.canUnfoldAll == true
        case #selector(foldLevel1(_:)),
             #selector(foldLevel2(_:)),
             #selector(foldLevel3(_:)),
             #selector(foldLevel4(_:)),
             #selector(foldLevel5(_:)):
            return focusedViewModel?.canFoldAll == true
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    /// One NSUndoManager registration per new UndoStack entry, replayed
    /// through the rope. `isUndoing` discriminates the redo direction;
    /// each replay re-registers so the chain continues both ways. Wired
    /// on `documentModel` directly (not any one pane's `EditorViewModel`
    /// passthrough) since it's the single source shared by every pane.
    @MainActor
    private func wireUndoCallback() {
        documentModel?.onNewUndoEntry = { [weak self] in
            self?.registerUndoReplay()
        }
    }

    @MainActor
    private func registerUndoReplay() {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                if document.undoManager?.isUndoing == true {
                    document.focusedViewModel?.undo()
                } else {
                    document.focusedViewModel?.redo()
                }
                document.registerUndoReplay()
            }
        }
    }
}
