// swiftlint:disable file_length
import AppKit
import Combine
import DocumentCore
import EditorUI
import FileKit
import SearchKit
import SwiftUI
import ThemeKit
import WorkspaceUI

/// Errors that block opening a document, with user-facing text.
enum DocumentOpenError: LocalizedError {
    /// File exceeds the openable-file ceiling (bytes given).
    case tooLarge(byteSize: Int)
    /// A single line exceeds the pathological-line threshold (ADR 0009:
    /// a 100 MB single-line file drives TextKit RSS to 11 GB).
    case lineTooLong(utf8Length: Int)

    var errorDescription: String? {
        switch self {
        case let .tooLarge(byteSize):
            "This file is \(byteSize / (1024 * 1024)) MB. Meridian opens files "
                + "up to 100 MB. Larger files are refused rather than opened "
                + "slowly — use a streaming viewer such as `less` for them."
        case let .lineTooLong(utf8Length):
            "This file's longest line is \(utf8Length / (1024 * 1024)) MB. "
                + "Meridian cannot open it yet — laying out one enormous line "
                + "blocks the app for minutes with no progress or cancel."
        }
    }
}

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
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

private final class RootSplitViewDelegate: NSObject, NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        100
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        max(150, splitView.bounds.height - 80)
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        true
    }
}

/// The NSDocument bridge: FileKit I/O on the outside, a `DocumentModel`
/// (shared buffer/undo) plus one or two `EditorViewModel` panes (each its
/// own engine + display settings) as the authoritative model, thin
/// NSUndoManager actions replaying the rope's UndoStack (spec decision 3).
final class MeridianDocument: NSDocument {
    // swiftlint:disable:previous type_body_length
    /// Hard ceiling on a file Meridian will open, in bytes.
    ///
    /// Files above this are refused rather than opened slowly: measurement
    /// during M10 showed a 700 MB file taking over five minutes to become
    /// visible and 4.7x its size in resident memory. Refusing is the honest
    /// behaviour; the previous 2 GB limit promised a capability the app does
    /// not have. Raising this later means implementing mapped rope leaves and
    /// a windowed text mirror first (ADR 0011).
    nonisolated static let maxFileSize = 100 * 1024 * 1024

    /// Hard ceiling on a single line's length, in UTF-8 bytes (1 MiB).
    ///
    /// Aligned with `HugeFileProfile.pathologicalLineBytes`. A file whose longest
    /// line reaches this is refused, because laying out one enormous line
    /// blocks the main run loop for minutes with no progress and no cancel —
    /// measurably worse than an immediate, honest refusal (ADR 0011).
    nonisolated static let maxLineLength = HugeFileProfile.pathologicalLineBytes

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
    private var containerStack: NSStackView?
    private var statusBarHost: NSHostingView<StatusBarView>?
    /// Persistently hosted (never added/removed): its SwiftUI body reads
    /// `HugeFileBannerHost.viewModel.isHugeFileBannerVisible` directly, so
    /// the banner appears/disappears reactively as that `@Observable`
    /// state changes, rather than needing an explicit show/hide call each
    /// time — see `refreshHugeFileBanner()` for the one thing that DOES
    /// need to be explicit: rebinding to a new `EditorViewModel` instance.
    private var bannerHost: NSHostingView<HugeFileBannerHost>?
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
    /// The buffer state as of the last open or save operation.
    private var savedBuffer = TextBuffer()
    /// The restriction profile of the file most recently read from disk.
    private var loadedProfile: HugeFileProfile = .unrestricted

    override var isDocumentEdited: Bool {
        guard let documentModel else { return super.isDocumentEdited }
        return !documentModel.buffer.contentEquals(savedBuffer)
    }

    private let fileTreeViewModel = FileTreeViewModel()
    private var sidebarHost: NSHostingView<FileTreeView>?
    private var rootSplitView: NSSplitView?
    private var rootSplitDelegate: RootSplitViewDelegate?
    var isSidebarVisible = false

    /// Subscription token for the FavoritesStore publisher so the window
    /// title refreshes immediately when the user adds/removes a favourite.
    private var favoritesCancellable: (any Sendable)?

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

    override var fileURL: URL? {
        didSet {
            if let fileURL {
                let folderURL = fileURL.deletingLastPathComponent()
                let accessing = folderURL.startAccessingSecurityScopedResource()
                Task { @MainActor in
                    self.fileTreeViewModel.setRootURL(folderURL)
                    if accessing {
                        folderURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }
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
            savedBuffer = file.buffer
            loadedProfile = file.profile
            fileTreeViewModel.setRootURL(url.deletingLastPathComponent())
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
            // Set on the engine BEFORE `EditorViewModel.init` triggers its
            // synchronous `load(buffer:)` — that call ends by starting a
            // parse if the engine's capabilities allow it, so the profile
            // must already be in force here or a huge file's first load
            // (including every revert, which reuses this engine) launches
            // one whole-file parse before anything gets a chance to
            // forbid it. Setting `newViewModel.hugeFileProfile` below is
            // still needed for the view-model-side state (soft wrap
            // clamping, banner visibility) — it is just too late to gate
            // the engine's first load.
            primaryEngine.profile = loadedProfile
            let newViewModel = EditorViewModel(documentModel: newDocumentModel, engine: primaryEngine)
            newViewModel.hugeFileProfile = loadedProfile
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
            refreshHugeFileBanner()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let buffer = MainActor.assumeIsolated { documentModel?.buffer } ?? pendingBuffer
        let metadata = loadedMetadata ?? (.utf8, false)
        do {
            return try TextFileIO.encode(buffer, as: metadata.encoding, includeBOM: metadata.hadBOM)
        } catch let FileKitError.unencodable(encoding) {
            let desc = "The document contains characters that cannot be represented in "
                + "\(encoding.displayName). Please select a Unicode encoding like UTF-8 before saving."
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteInapplicableStringEncodingError,
                userInfo: [NSLocalizedDescriptionKey: desc],
            )
        }
    }

    override func write(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        originalContentsURL absoluteOriginalContentsURL: URL?,
    ) throws {
        try super.write(
            to: url,
            ofType: typeName,
            for: saveOperation,
            originalContentsURL: absoluteOriginalContentsURL,
        )
        MainActor.assumeIsolated {
            if let currentBuffer = documentModel?.buffer {
                savedBuffer = currentBuffer
            }
        }
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            // Inject the shared favourites store before the sidebar is built.
            fileTreeViewModel.favoritesStore = AppDelegate.favoritesStore
            let documentModel = DocumentModel(buffer: pendingBuffer)
            self.documentModel = documentModel
            self.savedBuffer = pendingBuffer
            let engine = makeEngine(languageID: fileURL.flatMap { languageID(forFileExtension: $0.pathExtension) })
            // Must precede `EditorViewModel.init` — see the matching
            // comment in `read(from:ofType:)`. `loadedProfile` was already
            // populated by `read(from:ofType:)`, which NSDocument runs
            // before `makeWindowControllers()` for a file opened from
            // disk; it stays `.unrestricted` for a brand-new document.
            engine.profile = loadedProfile
            let viewModel = EditorViewModel(documentModel: documentModel, engine: engine)
            viewModel.hugeFileProfile = loadedProfile
            viewModel.isSoftWrapEnabled = AppDelegate.settingsStore.current.editor.softWrapDefault
            panes = [(viewModel, engine)]
            wireUndoCallback()
            wireMirroring()
            wireFocusTracking()
            refreshGitGutter()

            let host = makeStatusBarHost(viewModel: viewModel)
            statusBarHost = host

            let containerStack = NSStackView(views: [engine.view, host])
            containerStack.orientation = .vertical
            containerStack.spacing = 0
            containerStack.alignment = .width
            self.containerStack = containerStack
            editorSlotView = engine.view
            host.setContentHuggingPriority(.required, for: .vertical)

            let bannerHostView = NSHostingView(rootView: HugeFileBannerHost(viewModel: viewModel))
            bannerHost = bannerHostView
            containerStack.insertView(bannerHostView, at: 0, in: .top)

            let verticalRootSplitView = makeRootSplitView(containerStack: containerStack)

            NSWindow.allowsAutomaticWindowTabbing = true
            let window = MeridianWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1300, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false,
            )
            window.tabbingMode = .preferred
            window.titleVisibility = .hidden
            window.center()
            window.contentView = verticalRootSplitView

            let toolbar = ToolbarBuilder.makeToolbar()
            toolbar.delegate = self
            window.toolbar = toolbar
            window.toolbarStyle = .expanded

            let windowController = NSWindowController(window: window)
            windowController.shouldCascadeWindows = true
            addWindowController(windowController)
            refreshWindowTitle()
        }
    }

    private func makeRootSplitView(containerStack: NSStackView) -> WideDividerSplitView {
        let mainSplitView = makeSidebarSplitView(containerStack: containerStack)
        let verticalRootSplitView = WideDividerSplitView()
        verticalRootSplitView.isVertical = false
        verticalRootSplitView.dividerStyle = .thin
        verticalRootSplitView.addArrangedSubview(mainSplitView)
        let splitDelegate = RootSplitViewDelegate()
        verticalRootSplitView.delegate = splitDelegate
        rootSplitDelegate = splitDelegate
        rootSplitView = verticalRootSplitView
        return verticalRootSplitView
    }

    private func makeStatusBarHost(viewModel: EditorViewModel) -> NSHostingView<StatusBarView> {
        let currentEnc = loadedMetadata?.encoding ?? .utf8
        let hadBOM = loadedMetadata?.hadBOM ?? false
        let encodingName = currentEnc.formattedDisplayName(includeBOM: hadBOM)
        let statusBar = StatusBarView(
            viewModel: viewModel,
            encodingName: encodingName,
            lineEndingName: "LF",
            currentEncoding: currentEnc,
            currentIncludeBOM: hadBOM,
            gitBranchName: currentGitBranchName,
            onSelectEncoding: { [weak self] newEncoding, includeBOM in
                self?.changeEncoding(to: newEncoding, includeBOM: includeBOM)
            },
            onReopenWithEncoding: { [weak self] newEncoding in
                self?.reopen(with: newEncoding)
            },
        )
        return NSHostingView(rootView: statusBar)
    }

    private func makeSidebarSplitView(containerStack: NSStackView) -> NSSplitView {
        let sidebarView = FileTreeView(viewModel: fileTreeViewModel)
        let sidebarHost = NSHostingView(rootView: sidebarView)
        self.sidebarHost = sidebarHost
        sidebarHost.isHidden = !isSidebarVisible

        let mainSplitView = NSSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.addArrangedSubview(sidebarHost)
        mainSplitView.addArrangedSubview(containerStack)

        sidebarHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        sidebarHost.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        containerStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        let initialFolder = fileURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        fileTreeViewModel.setRootURL(initialFolder)

        fileTreeViewModel.onSelectFile = { [weak self] selectedURL in
            guard selectedURL != self?.fileURL else { return }
            NSDocumentController.shared.openDocument(withContentsOf: selectedURL, display: true) { _, _, _ in }
        }
        fileTreeViewModel.onOpenFavorite = { [weak self] selectedURL in
            guard selectedURL != self?.fileURL else { return }
            NSDocumentController.shared.openDocument(withContentsOf: selectedURL, display: true) { _, _, _ in }
        }
        fileTreeViewModel.onToggleSidebar = { [weak self] in
            self?.toggleSidebar(nil)
        }

        // Subscribe to FavoritesStore changes to keep the window title star in sync.
        favoritesCancellable = AppDelegate.favoritesStore.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.refreshWindowTitle()
            }
        }

        // Apply initial sidebar visibility after layout is done.
        if !isSidebarVisible {
            DispatchQueue.main.async {
                sidebarHost.isHidden = true
                mainSplitView.adjustSubviews()
            }
        }

        return mainSplitView
    }

    override func showWindows() {
        super.showWindows()
        for controller in windowControllers {
            if let window = controller.window {
                window.tabbingMode = .preferred
                DispatchQueue.main.async {
                    if window.tabGroup?.isTabBarVisible != true {
                        window.toggleTabBar(nil)
                    }
                }
            }
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

    @objc func toggleSidebar(_ sender: Any?) {
        isSidebarVisible.toggle()
        if let sidebarHost {
            sidebarHost.isHidden = !isSidebarVisible
            if let splitView = sidebarHost.superview as? NSSplitView {
                splitView.adjustSubviews()
            }
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdaterService.shared.checkForUpdates()
    }

    override var displayName: String? {
        get {
            super.displayName
        }
        set {
            super.displayName = newValue
        }
    }

    /// Toggles the current document's favourite state and updates the
    /// window title to show or hide the ⭐ suffix.
    @objc func toggleFavorite(_ sender: Any?) {
        guard let url = fileURL else { return }
        AppDelegate.favoritesStore.toggle(url)
        refreshWindowTitle()
    }

    /// Refreshes the window title and representedURL so the native macOS Tab
    /// renders the exact system file extension icon on the leading (left) side of the title.
    private func refreshWindowTitle() {
        guard let window = windowControllers.first?.window else { return }
        window.representedURL = fileURL
        window.tab.accessoryView = nil
        let baseName = super.displayName ?? "Untitled"
        let suffix = (fileURL != nil && AppDelegate.favoritesStore.isFavorite(fileURL!)) ? " ⭐" : ""
        window.title = baseName + suffix
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
            // Must precede `EditorViewModel.init` — see the matching
            // comment in `read(from:ofType:)`: the engine's `load(buffer:)`
            // (triggered synchronously by that init) starts a parse gated
            // on `engine.activeCapabilities`, so an unrestricted default
            // here would launch one whole-file parse on the new pane
            // before anything gets a chance to forbid it.
            secondaryEngine.profile = primary.viewModel.hugeFileProfile
            let secondaryViewModel = EditorViewModel(documentModel: documentModel, engine: secondaryEngine)
            // Must be set before `isSoftWrapEnabled` below: the profile's
            // own didSet re-clamps soft wrap, and a huge-file document
            // must gate the split pane's engine the same as the primary's
            // (or its syntax highlighter would keep running unrestricted).
            // `inheritHugeFileState` also carries over an already-accepted
            // "Enable Anyway" override and the banner's dismissal state —
            // plain `hugeFileProfile = ...` would silently reset both.
            secondaryViewModel.inheritHugeFileState(from: primary.viewModel)
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
        refreshHugeFileBanner()
    }

    /// Swaps whatever currently occupies the container stack's top slot
    /// (a single pane's view, or a previous split view) for the correct
    /// view given `panes.count` and `currentSplitOrientation`.
    private func rebuildSplitLayout() {
        guard windowControllers.first?.window != nil,
              let containerStack
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
        // Insert below any open overlay (find bar / command palette) and
        // below the huge-file banner host — both currently occupy slots
        // above the editor and must stay there, not be displaced. The
        // banner host is inserted once in `makeWindowControllers()` and
        // never removed (its visibility is controlled by SwiftUI content,
        // not by adding/removing the arranged subview), so it is always
        // present by the time a split can happen; the `nil` check is just
        // defensive.
        let overlayIsOpen = findBarHost != nil || commandPalettePanel != nil
        let insertIndex = (overlayIsOpen ? 1 : 0) + (bannerHost != nil ? 1 : 0)
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
                updateMarkdownPreviewIfActive()
                refreshGitGutter()
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
                self?.refreshHugeFileBanner()
            }
        }
    }

    private func refreshStatusBar() {
        guard let host = statusBarHost, let viewModel = focusedViewModel else { return }
        let currentEnc = loadedMetadata?.encoding ?? .utf8
        let hadBOM = loadedMetadata?.hadBOM ?? false
        let encodingName = currentEnc.formattedDisplayName(includeBOM: hadBOM)
        host.rootView = StatusBarView(
            viewModel: viewModel,
            encodingName: encodingName,
            lineEndingName: "LF",
            currentEncoding: currentEnc,
            currentIncludeBOM: hadBOM,
            gitBranchName: currentGitBranchName,
            onSelectEncoding: { [weak self] newEncoding, includeBOM in
                self?.changeEncoding(to: newEncoding, includeBOM: includeBOM)
            },
            onReopenWithEncoding: { [weak self] newEncoding in
                self?.reopen(with: newEncoding)
            },
        )
        // Reconcile visibility with the newly-focused pane's own toggle —
        // without this, hiding the bar while pane A is focused then
        // switching focus to pane B (whose isStatusBarVisible is still
        // true) would leave the bar hidden despite the View-menu checkmark
        // (which reads focusedViewModel.isStatusBarVisible) showing "on".
        host.isHidden = !viewModel.isStatusBarVisible
    }

    /// Rebinds the huge-file banner host to the currently focused pane's
    /// view model — needed alongside `refreshStatusBar()` at every point
    /// that can replace or add an `EditorViewModel` (revert, reopen with
    /// a different encoding, split, focus change): the host's SwiftUI
    /// tree otherwise keeps observing a stale instance. Visibility itself
    /// does NOT need an explicit refresh — `HugeFileBannerHost`'s body
    /// reads `isHugeFileBannerVisible` directly and reacts on its own.
    private func refreshHugeFileBanner() {
        guard let viewModel = focusedViewModel else { return }
        bannerHost?.rootView = HugeFileBannerHost(viewModel: viewModel)
    }

    func changeEncoding(to newEncoding: TextEncoding, includeBOM: Bool) {
        loadedMetadata = (newEncoding, includeBOM)
        updateChangeCount(.changeDone)
        refreshStatusBar()
    }

    func reopen(with encoding: TextEncoding) {
        guard let url = fileURL else { return }
        do {
            let file = try TextFileIO.loadTextFile(at: url, overrideEncoding: encoding)
            guard file.longestLineUTF8Length < Self.maxLineLength else {
                throw DocumentOpenError.lineTooLong(utf8Length: file.longestLineUTF8Length)
            }
            loadedMetadata = (file.encoding, file.hadBOM)
            pendingBuffer = file.buffer
            savedBuffer = file.buffer
            loadedProfile = file.profile
            let newDocumentModel = DocumentModel(buffer: file.buffer)
            documentModel = newDocumentModel
            if !panes.isEmpty {
                let primaryEngine = panes[0].engine
                // Must precede `EditorViewModel.init` — see the matching
                // comment in `read(from:ofType:)`.
                primaryEngine.profile = loadedProfile
                let newViewModel = EditorViewModel(documentModel: newDocumentModel, engine: primaryEngine)
                newViewModel.hugeFileProfile = loadedProfile
                newViewModel.isSoftWrapEnabled = AppDelegate.settingsStore.current.editor.softWrapDefault
                panes[0] = (newViewModel, primaryEngine)
                wireUndoCallback()
                wireMirroring()
                wireFocusTracking()
            }
            refreshStatusBar()
            refreshHugeFileBanner()
        } catch {
            let alert = NSAlert(error: error)
            if let window = windowControllers.first?.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    private var findBarHost: NSHostingView<FindBarView>?
    /// Owns Find & Replace's search/navigation state — see
    /// `FindBarViewModel`'s doc comment for why this lives here rather
    /// than as `FindBarView`'s private `@State`.
    private var findBarViewModel: FindBarViewModel?

    @objc func performFind(_ sender: Any?) {
        if findBarHost != nil {
            hideFindBar()
        } else {
            showFindBar(startExpanded: false)
        }
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

    private var commandPalettePanel: NSPanel?
    private var lastCommandPaletteDismissTime: Date?
    /// Local mouse-down monitor that dismisses the palette on click-outside
    /// (spec: "The palette closes on Esc, on executing a command, or on
    /// click-outside"). Installed only while the palette is open; removed
    /// in `hideCommandPalette()` so it never lingers over normal editing.
    private var commandPaletteClickMonitor: Any?

    @objc func showCommandPalette(_ sender: Any?) {
        if commandPalettePanel != nil {
            hideCommandPalette()
            return
        }
        if let lastDismiss = lastCommandPaletteDismissTime, Date().timeIntervalSince(lastDismiss) < 0.6 {
            lastCommandPaletteDismissTime = nil
            return
        }
        guard let window = windowControllers.first?.window else { return }

        let viewModel = CommandPaletteViewModel(commands: CommandRegistry.commands)
        let paletteView = CommandPaletteView(
            viewModel: viewModel,
            onExecute: { [weak self] in
                guard let self, let command = viewModel.selectedCommand else { return }
                hideCommandPalette()
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

        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 360

        let hostingView = NSHostingView(rootView: paletteView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel = createCommandPalettePanel(hostingView: hostingView, width: panelWidth, height: panelHeight)
        commandPalettePanel = panel

        let windowFrame = window.frame
        let panelX = windowFrame.origin.x + (windowFrame.width - panelWidth) / 2
        let panelY = windowFrame.origin.y + windowFrame.height - panelHeight - 90

        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)

        commandPaletteClickMonitor = NSEvent
            .addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let currentPanel = commandPalettePanel else { return event }
                if event.window !== currentPanel {
                    lastCommandPaletteDismissTime = Date()
                    hideCommandPalette()
                }
                return event
            }
    }

    private func hideCommandPalette() {
        if let monitor = commandPaletteClickMonitor {
            NSEvent.removeMonitor(monitor)
            commandPaletteClickMonitor = nil
        }
        if let panel = commandPalettePanel {
            if let window = windowControllers.first?.window {
                window.removeChildWindow(panel)
                window.makeKey()
            }
            panel.orderOut(nil)
            panel.close()
            commandPalettePanel = nil
            windowControllers.first?.window?.makeFirstResponder(focusedEngine?.keyView)
        }
    }

    private func createCommandPalettePanel(
        hostingView: NSView,
        width: CGFloat,
        height: CGFloat,
    ) -> CommandPalettePanel {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        return panel
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

    // MARK: - Markdown Formatting Commands

    @objc func insertMarkdownBold(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.wrapSelection(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "**", suffix: "**",
        ))
    }

    @objc func insertMarkdownItalic(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.wrapSelection(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "*", suffix: "*",
        ))
    }

    @objc func insertMarkdownStrikethrough(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.wrapSelection(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "~~", suffix: "~~",
        ))
    }

    @objc func insertMarkdownHeading1(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "# ",
        ))
    }

    @objc func insertMarkdownHeading2(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "## ",
        ))
    }

    @objc func insertMarkdownHeading3(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "### ",
        ))
    }

    @objc func insertMarkdownList(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "- ",
        ))
    }

    @objc func insertMarkdownOrderedList(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "1. ",
        ))
    }

    @objc func insertMarkdownBlockquote(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertLinePrefix(
            in: viewModel.buffer, selection: viewModel.selection, prefix: "> ",
        ))
    }

    @objc func insertMarkdownLink(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertMarkdownLink(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func insertMarkdownCode(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertMarkdownCode(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func insertMarkdownHorizontalRule(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertMarkdownHorizontalRule(
            in: viewModel.buffer, selection: viewModel.selection,
        ))
    }

    @objc func insertMarkdownTable(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.insertMarkdownTable(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func addCaretAbove(_ sender: Any?) {
        focusedViewModel?.addCaretAbove()
    }

    @objc func addCaretBelow(_ sender: Any?) {
        focusedViewModel?.addCaretBelow()
    }

    @objc func selectNextOccurrence(_ sender: Any?) {
        focusedViewModel?.selectNextOccurrence()
    }

    @objc func selectAllOccurrences(_ sender: Any?) {
        focusedViewModel?.selectAllOccurrences()
    }

    @objc func sortLinesAscending(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.sortLines(
            in: viewModel.buffer,
            selection: viewModel.selection,
            ascending: true,
        ))
    }

    @objc func sortLinesDescending(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.sortLines(
            in: viewModel.buffer,
            selection: viewModel.selection,
            ascending: false,
        ))
    }

    @objc func deduplicateLines(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        viewModel.perform(TextTransforms.deduplicateLines(in: viewModel.buffer, selection: viewModel.selection))
    }

    private var markdownPreviewHost: NSHostingView<MarkdownPreviewView>?

    @objc func formatDocument(_ sender: Any?) {
        formatCurrentDocument(pretty: true)
    }

    @objc func minifyDocument(_ sender: Any?) {
        formatCurrentDocument(pretty: false)
    }

    private func formatCurrentDocument(pretty: Bool) {
        guard let viewModel = focusedViewModel else {
            Swift.print("[Meridian Debug] formatCurrentDocument failed: focusedViewModel is nil")
            return
        }
        let currentText = viewModel.buffer.string
        let langID = panes.first?.engine.languageID ?? fileURL?.pathExtension
        let fileName = fileURL?.lastPathComponent ?? "Untitled"
        let language = langID ?? "nil"
        Swift.print(
            "[Meridian Debug] formatCurrentDocument: file='\(fileName)', langID='\(language)', pretty=\(pretty)",
        )

        let result = DocumentFormatter.formatResult(text: currentText, languageID: langID, pretty: pretty)
        switch result {
        case let .success(formatted):
            let singleCaret = SelectionSet(caretAt: ByteOffset(0))
            viewModel.setSelection(singleCaret)
            let fullRange = ByteOffset(0) ..< ByteOffset(viewModel.buffer.utf8Count)
            let edit = Edit(range: fullRange, replacement: formatted)
            let transaction = EditTransaction(
                baseVersion: viewModel.buffer.version,
                edits: [edit],
                selectionBefore: singleCaret,
                selectionAfter: singleCaret,
            )
            viewModel.perform(transaction)
            viewModel.setSelection(singleCaret)
            DispatchQueue.main.async { [weak viewModel] in
                viewModel?.setSelection(singleCaret)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak viewModel] in
                viewModel?.setSelection(singleCaret)
            }
            Swift.print("[Meridian Debug] formatCurrentDocument: Format transaction performed successfully!")
        case let .failure(error):
            Swift.print("[Meridian Debug] formatCurrentDocument: \(error.localizedDescription)")
            NSSound.beep()
            showFormatErrorAlert(reason: error.localizedDescription)
        }
    }

    private func showFormatErrorAlert(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot Format Document"
        alert.informativeText = reason
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        guard let viewModel = focusedViewModel else {
            Swift.print("[Meridian Debug] toggleMarkdownPreview failed: focusedViewModel is nil")
            return
        }
        Swift.print(
            "[Meridian Debug] toggleMarkdownPreview called. currentlyOpen=\(markdownPreviewHost != nil)",
        )
        if let previewHost = markdownPreviewHost {
            previewHost.removeFromSuperview()
            markdownPreviewHost = nil
            Swift.print("[Meridian Debug] Closed MarkdownPreviewView")
        } else {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            let preview = MarkdownPreviewView(markdownText: viewModel.buffer.string, isDarkMode: isDark)
            let host = NSHostingView(rootView: preview)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
            markdownPreviewHost = host

            let splitView = (sidebarHost?.superview as? NSSplitView)
                ?? (editorSlotView?.superview as? NSSplitView)
                ?? (editorSlotView?.superview?.superview as? NSSplitView)
            if let splitView {
                splitView.addArrangedSubview(host)
                let totalWidth = splitView.bounds.width
                if totalWidth > 500 {
                    splitView.setPosition(totalWidth * 0.5, ofDividerAt: splitView.arrangedSubviews.count - 2)
                }
                splitView.adjustSubviews()
                Swift.print("[Meridian Debug] Added MarkdownPreviewView to splitView successfully with 50% ratio!")
            } else {
                Swift.print("[Meridian Debug] toggleMarkdownPreview error: Could not find parent NSSplitView")
            }
        }
    }

    private var hexInspectorHost: NSView?

    @objc func toggleHexView(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        if let host = hexInspectorHost {
            host.removeFromSuperview()
            hexInspectorHost = nil
        } else {
            let data = Data(viewModel.buffer.string.utf8)
            let name = fileURL?.lastPathComponent ?? "Untitled"
            let hexView = HexInspectorView(data: data, fileName: name)
            let host = NSHostingView(rootView: hexView)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.widthAnchor.constraint(greaterThanOrEqualToConstant: 450).isActive = true
            hexInspectorHost = host

            let splitView = (sidebarHost?.superview as? NSSplitView)
                ?? (editorSlotView?.superview as? NSSplitView)
                ?? (editorSlotView?.superview?.superview as? NSSplitView)
            if let splitView {
                splitView.addArrangedSubview(host)
                let totalWidth = splitView.bounds.width
                if totalWidth > 600 {
                    splitView.setPosition(totalWidth * 0.5, ofDividerAt: splitView.arrangedSubviews.count - 2)
                }
                splitView.adjustSubviews()
            }
        }
    }

    private var minimapHost: NSView?

    @objc func toggleMinimap(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        // Closing an already-open minimap must always be allowed: the
        // capability can go from permitted to forbidden out from under an
        // open minimap (e.g. a revert that turns the document huge), and
        // gating the close branch on the same guard as the open branch
        // would strand the user with an open minimap and no way to turn
        // it off (`validateMenuItem` would also grey out the menu item).
        if let host = minimapHost {
            host.removeFromSuperview()
            minimapHost = nil
            focusedEngine?.onScrollChange = nil
        } else {
            guard viewModel.effectiveCapabilities.minimap else {
                NSSound.beep()
                return
            }
            let lines = viewModel.buffer.string.components(separatedBy: .newlines)
            let minimapModel = MinimapViewModel(lines: lines)
            let minimap = MinimapView(model: minimapModel) { [weak self] targetLine in
                guard let self, let viewModel = focusedViewModel else { return }
                let maxLine = max(0, viewModel.buffer.lineCount - 1)
                let clampedLine = max(0, min(targetLine, maxLine))
                let pos = LinePosition(line: clampedLine, utf16Column: 0)
                let byteOffset = viewModel.buffer.byteOffset(of: pos)
                focusedEngine?.scrollTo(byteOffset, in: viewModel.buffer)
            }
            let host = NSHostingView(rootView: minimap)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.widthAnchor.constraint(equalToConstant: 80).isActive = true
            minimapHost = host

            // Sync viewport highlight synchronously on every scroll event (same render pass)
            focusedEngine?.onScrollChange = { [weak minimapModel] range in
                minimapModel?.visibleLineRange = range
            }
            focusedEngine?.handleScrollBoundsChange()

            let splitView = (sidebarHost?.superview as? NSSplitView)
                ?? (editorSlotView?.superview as? NSSplitView)
                ?? (editorSlotView?.superview?.superview as? NSSplitView)
            splitView?.addArrangedSubview(host)
            splitView?.adjustSubviews()
        }
    }

    private var terminalHost: NSView?

    @objc func toggleTerminal(_ sender: Any?) {
        if let host = terminalHost {
            host.removeFromSuperview()
            terminalHost = nil
            rootSplitView?.adjustSubviews()
        } else {
            guard let rootSplitView else { return }
            let terminal = TerminalView(documentURL: fileURL)
            let host = NSHostingView(rootView: terminal)
            terminalHost = host

            rootSplitView.addArrangedSubview(host)
            rootSplitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
            rootSplitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 1)

            let totalHeight = rootSplitView.bounds.height
            let targetDividerPos = max(100, totalHeight - 300)
            rootSplitView.setPosition(targetDividerPos, ofDividerAt: 0)
            rootSplitView.adjustSubviews()

            DispatchQueue.main.async { [weak self] in
                guard let self, let rootSplitView = self.rootSplitView, terminalHost != nil else { return }
                let currentHeight = rootSplitView.bounds.height
                if currentHeight > 300 {
                    rootSplitView.setPosition(currentHeight - 300, ofDividerAt: 0)
                    rootSplitView.adjustSubviews()
                }
            }
        }
    }

    private var diffWindowControllers: [NSWindowController] = []

    @objc func compareWithFile(_ sender: Any?) {
        guard let viewModel = focusedViewModel else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a file to compare against the current document"

        panel.begin { [weak self] response in
            guard response == .OK, let targetURL = panel.url, let self else { return }
            do {
                let targetText = try String(contentsOf: targetURL, encoding: .utf8)
                let currentText = viewModel.buffer.string
                let leftName = fileURL?.lastPathComponent ?? "Untitled"
                let rightName = targetURL.lastPathComponent

                let result = DiffEngine.diff(
                    leftText: currentText,
                    rightText: targetText,
                    leftName: leftName,
                    rightName: rightName,
                )
                let controller = DiffWindowController(diffResult: result)
                diffWindowControllers.append(controller)
                controller.showWindow(sender)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could Not Read Compare File"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func updateMarkdownPreviewIfActive() {
        guard let previewHost = markdownPreviewHost, let viewModel = focusedViewModel else { return }
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
        previewHost.rootView = MarkdownPreviewView(markdownText: viewModel.buffer.string, isDarkMode: isDark)
    }

    private var gitGutterMarks: [Int: GitGutterMark] = [:]
    private var currentGitBranchName: String?

    private func refreshGitBranch() {
        guard let url = fileURL else {
            currentGitBranchName = nil
            refreshStatusBar()
            return
        }
        let directory = url.deletingLastPathComponent()
        Task { @MainActor in
            let branch = await GitService.shared.currentBranch(in: directory)
            self.currentGitBranchName = branch
            self.refreshStatusBar()
        }
    }

    private func refreshGitGutter() {
        refreshGitBranch()
        guard let url = fileURL, let viewModel = focusedViewModel,
              viewModel.effectiveCapabilities.gitGutter
        else {
            gitGutterMarks = [:]
            updateGitGutterMarkProviders()
            return
        }
        let bufferText = viewModel.buffer.string
        Task { @MainActor in
            let marks = await GitService.shared.diffStatus(bufferText: bufferText, fileURL: url)
            self.gitGutterMarks = marks
            self.updateGitGutterMarkProviders()
        }
    }

    private func updateGitGutterMarkProviders() {
        for pane in panes {
            pane.engine.setGitGutterMarkProvider { [weak self] line in
                self?.gitGutterMarks[line] ?? .none
            }
        }
    }

    private func showFindBar(startExpanded: Bool) {
        guard let viewModel = focusedViewModel, findBarHost == nil else { return }
        if let findBarViewModel, !findBarViewModel.isBound(to: viewModel) {
            self.findBarViewModel = nil
        }
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

        if let window = windowControllers.first?.window, let containerStack {
            containerStack.insertView(host, at: 0, in: .top)
            window.makeFirstResponder(host)
        }
    }

    private var findInFilesWindowController: NSWindowController?

    @objc func performFindInFiles(_ sender: Any?) {
        showFindInFilesWindow()
    }

    private func showFindInFilesWindow() {
        if let controller = findInFilesWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let folder = findWorkspaceFolder()
        let vm = FindInFilesViewModel(searchFolder: folder)
        vm.onSelectMatch = { [weak self] fileURL, match in
            self?.openAndSelectMatch(fileURL: fileURL, match: match)
        }

        let view = FindInFilesView(viewModel: vm)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Find in Files — Meridian"
        window.setContentSize(NSSize(width: 450, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]

        let controller = NSWindowController(window: window)
        findInFilesWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func openAndSelectMatch(fileURL: URL, match: FileMatch) {
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { doc, _, _ in
            if let document = doc as? MeridianDocument, let vm = document.focusedViewModel {
                let range = match.range
                vm.setSelection(SelectionSet(ranges: [range]))
            }
        }
    }

    private func findWorkspaceFolder() -> URL {
        if let fileURL {
            var current = fileURL.deletingLastPathComponent()
            let fm = FileManager.default
            while current.path != "/", current.path.count > 1 {
                let gitPath = current.appendingPathComponent(".git").path
                let pkgPath = current.appendingPathComponent("Package.swift").path
                let projPath = current.appendingPathComponent("project.yml").path
                if fm.fileExists(atPath: gitPath) || fm.fileExists(atPath: pkgPath) || fm.fileExists(atPath: projPath) {
                    return current
                }
                current = current.deletingLastPathComponent()
            }
            return fileURL.deletingLastPathComponent()
        }
        let pwd = FileManager.default.currentDirectoryPath
        if !pwd.isEmpty {
            return URL(fileURLWithPath: pwd)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    private func hideFindBar() {
        if let host = findBarHost {
            host.removeFromSuperview()
            findBarHost = nil
            windowControllers.first?.window?.makeFirstResponder(focusedEngine?.keyView)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFavorite(_:)) {
            let isFav = fileURL.map { AppDelegate.favoritesStore.isFavorite($0) } ?? false
            menuItem.title = isFav ? "Remove from Favorites" : "Add to Favorites"
            return fileURL != nil
        }
        if let valid = validateEditorMenuItem(menuItem) {
            return valid
        }
        if let valid = validateFormatAndPreviewMenuItem(menuItem) {
            return valid
        }
        if let valid = validateFoldMenuItem(menuItem) {
            return valid
        }
        return super.validateMenuItem(menuItem)
    }

    private func validateFormatAndPreviewMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(formatDocument(_:)), #selector(minifyDocument(_:)), #selector(compareWithFile(_:)):
            return focusedViewModel != nil
        case #selector(toggleMarkdownPreview(_:)):
            menuItem.state = (markdownPreviewHost != nil) ? .on : .off
            return focusedViewModel != nil
        case #selector(toggleHexView(_:)):
            menuItem.state = (hexInspectorHost != nil) ? .on : .off
            return focusedViewModel != nil
        case #selector(toggleMinimap(_:)):
            menuItem.state = (minimapHost != nil) ? .on : .off
            // Stay enabled while the minimap is already open even if the
            // capability has since gone false — closing it must always be
            // possible (see `toggleMinimap`'s doc comment).
            return minimapHost != nil || focusedViewModel?.effectiveCapabilities.minimap == true
        case #selector(toggleTerminal(_:)):
            menuItem.state = (terminalHost != nil) ? .on : .off
            return true
        default:
            return nil
        }
    }

    private func validateEditorMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !(findBarViewModel?.matches.isEmpty ?? true)
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = (focusedViewModel?.isGutterVisible == true) ? .on : .off
            return true
        case #selector(toggleSoftWrap(_:)):
            menuItem.state = (focusedViewModel?.isSoftWrapEnabled == true) ? .on : .off
            return focusedViewModel?.effectiveCapabilities.softWrap == true
        case #selector(toggleStatusBar(_:)):
            menuItem.state = (focusedViewModel?.isStatusBarVisible == true) ? .on : .off
            return true
        case #selector(toggleSidebar(_:)):
            menuItem.state = isSidebarVisible ? .on : .off
            return true
        case #selector(checkForUpdates(_:)):
            return UpdaterService.shared.canCheckForUpdates
        case #selector(splitHorizontally(_:)):
            menuItem.state = (currentSplitOrientation == .horizontal) ? .on : .off
            return true
        case #selector(splitVertically(_:)):
            menuItem.state = (currentSplitOrientation == .vertical) ? .on : .off
            return true
        default:
            return nil
        }
    }

    private func validateFoldMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(foldCurrentRegion(_:)):
            focusedViewModel?.canFoldAtCaret == true
        case #selector(unfoldCurrentRegion(_:)):
            focusedViewModel?.canUnfoldAtCaret == true
        case #selector(foldAll(_:)), #selector(unfoldAll(_:)),
             #selector(foldLevel1(_:)), #selector(foldLevel2(_:)),
             #selector(foldLevel3(_:)), #selector(foldLevel4(_:)),
             #selector(foldLevel5(_:)):
            focusedViewModel?.canFoldAll == true
        default:
            nil
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
            self?.updateChangeCount(.changeDone)
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

extension MeridianDocument: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool,
    ) -> NSToolbarItem? {
        ToolbarBuilder.item(for: itemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ToolbarBuilder.defaultItemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ToolbarBuilder.allowedItemIdentifiers
    }

    /// Markdown items are only meaningful on a Markdown-language document
    /// (see `LanguageExtensionMap.swift`'s `.md`/`.markdown` → `"markdown"`
    /// mapping). Undo/Redo are NOT validated here despite having toolbar
    /// identifiers: `NSToolbarItem.validate()` resolves the `undo:`/`redo:`
    /// action's target through the responder chain, and that resolves to
    /// the document's `NSUndoManager` (via `NSDocument`'s default
    /// `supplementalTargetForAction(_:sender:)` wiring — see
    /// `registerUndoReplay()`/`wireUndoCallback()` above for how this
    /// document's undo manager is set up), never to `MeridianDocument`
    /// itself. Since `NSUndoManager` doesn't conform to
    /// `NSToolbarItemValidation`, `.undo`/`.redo` fall through to the
    /// `default` case below, which is a no-op here (AppKit decides their
    /// enabled state on its own). Everything else in this toolbar is
    /// enabled whenever a document pane is focused, same bar
    /// `validateMenuItem` already uses for the equivalent menu items —
    /// this deliberately does not attempt clipboard-empty detection for
    /// Cut/Copy/Paste, matching the fact that
    /// `validateEditorMenuItem`/`validateFormatAndPreviewMenuItem` don't
    /// validate those selectors either (NSTextView's own built-in
    /// validation already handles them ahead of `MeridianDocument` in the
    /// responder chain when a menu is involved; the toolbar has no such
    /// built-in path, so those three items stay enabled whenever a
    /// document is focused).
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .markdownBold, .markdownItalic, .markdownHeading, .markdownLink, .markdownList, .markdownCode,
             .markdownOrderedList, .markdownBlockquote, .markdownStrikethrough, .markdownHorizontalRule,
             .markdownTable:
            focusedEngine?.languageID == "markdown"
        default:
            focusedViewModel != nil
        }
    }
}

/// Wraps ``HugeFileBannerView`` so its presence, not just its content,
/// tracks `EditorViewModel`'s `@Observable` state: reading
/// `viewModel.isHugeFileBannerVisible` directly in `body` means SwiftUI
/// re-renders (and the hosting `NSStackView` collapses this to zero
/// height) the moment the profile changes, the user dismisses the
/// banner, or overrides the capabilities — with no imperative
/// insert/remove bookkeeping in `MeridianDocument` beyond rebinding
/// `viewModel` itself when a pane's view model instance changes (see
/// `MeridianDocument.refreshHugeFileBanner()`).
private struct HugeFileBannerHost: View {
    let viewModel: EditorViewModel

    var body: some View {
        if viewModel.isHugeFileBannerVisible {
            HugeFileBannerView(
                profile: viewModel.hugeFileProfile,
                effectiveCapabilities: viewModel.effectiveCapabilities,
                hasOverriddenCapabilities: viewModel.hasEnabledHeavyFeatureOverride,
                onOverride: { viewModel.overrideCapabilities() },
                onDismiss: { viewModel.isBannerDismissed = true },
            )
        }
    }
}

private struct SidebarLeadingTitlebarButton: View {
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar (⌘B)")
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
