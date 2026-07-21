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

/// The NSDocument bridge: FileKit I/O on the outside, EditorViewModel as
/// the authoritative model, thin NSUndoManager actions replaying the
/// rope's UndoStack (spec decision 3).
final class MeridianDocument: NSDocument {
    /// Huge-file threshold: at or above this size, refuse to open.
    nonisolated static let maxFileSize = 64 * 1024 * 1024
    /// Pathological-line threshold, in UTF-8 bytes.
    nonisolated static let maxLineLength = 1_000_000

    private var viewModel: EditorViewModel?
    private var engine: TextKit2Engine?
    private var statusBarHost: NSHostingView<StatusBarView>?
    /// Metadata from the loaded file (encoding/BOM for faithful save);
    /// nil for untitled documents (saved as UTF-8, no BOM, LF).
    private var loadedMetadata: (encoding: TextEncoding, hadBOM: Bool)?
    /// Buffer read before window controllers exist.
    private var pendingBuffer = TextBuffer()

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
            // Re-opened into an existing window (revert): reload the model.
            if let viewModel, let engine {
                // Rebuild rather than diff — P1 has no revert UI; this
                // path only runs for NSDocument's built-in revert.
                _ = viewModel // old model discarded with its undo history
                engine.languageID = languageID(forFileExtension: url.pathExtension)
                self.viewModel = EditorViewModel(buffer: file.buffer, engine: engine)
                self.wireUndoCallback()
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let buffer = MainActor.assumeIsolated { viewModel?.buffer } ?? pendingBuffer
        let metadata = loadedMetadata ?? (.utf8, false)
        return try TextFileIO.encode(buffer, as: metadata.encoding, includeBOM: metadata.hadBOM)
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            let engine = TextKit2Engine(themeEngine: AppDelegate.themeEngine, settingsStore: AppDelegate.settingsStore)
            engine.languageID = fileURL.flatMap { languageID(forFileExtension: $0.pathExtension) }
            let viewModel = EditorViewModel(buffer: pendingBuffer, engine: engine)
            self.engine = engine
            self.viewModel = viewModel
            wireUndoCallback()

            let encodingName = loadedMetadata?.encoding.displayName ?? "UTF-8"
            let statusBar = StatusBarView(
                viewModel: viewModel,
                encodingName: encodingName,
                lineEndingName: "LF",
            )
            let host = NSHostingView(rootView: statusBar)
            self.statusBarHost = host

            let containerStack = NSStackView(views: [engine.view, host])
            containerStack.orientation = .vertical
            containerStack.spacing = 0
            containerStack.alignment = .width
            engine.view.setContentHuggingPriority(.defaultLow, for: .vertical)
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
            engine.documentUndoManager = undoManager
            addWindowController(NSWindowController(window: window))
        }
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        viewModel?.isGutterVisible.toggle()
    }

    @objc func toggleSoftWrap(_ sender: Any?) {
        viewModel?.isSoftWrapEnabled.toggle()
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.isStatusBarVisible.toggle()
        statusBarHost?.isHidden = !viewModel.isStatusBarVisible
    }

    private var findBarHost: NSHostingView<FindBarView>?

    @objc func performFind(_ sender: Any?) {
        showFindBar()
    }

    @objc func performFindAndReplace(_ sender: Any?) {
        showFindBar()
    }

    @objc func duplicateLine(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.perform(TextTransforms.duplicateLines(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func deleteLine(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.perform(TextTransforms.deleteLines(in: viewModel.buffer, selection: viewModel.selection))
    }

    @objc func trimTrailingWhitespace(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.perform(TextTransforms.trimTrailingWhitespace(in: viewModel.buffer))
    }

    @objc func makeUpperCase(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel
            .perform(TextTransforms
                .transformCase(in: viewModel.buffer, selection: viewModel.selection) { $0.uppercased() })
    }

    @objc func makeLowerCase(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel
            .perform(TextTransforms
                .transformCase(in: viewModel.buffer, selection: viewModel.selection) { $0.lowercased() })
    }

    @objc func convertLineEndingsToLF(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.perform(TextTransforms.convertLineEndings(in: viewModel.buffer, to: .lf))
    }

    @objc func convertLineEndingsToCRLF(_ sender: Any?) {
        guard let viewModel else { return }
        viewModel.perform(TextTransforms.convertLineEndings(in: viewModel.buffer, to: .crlf))
    }

    private func showFindBar() {
        guard let viewModel, findBarHost == nil else { return }
        let findView = FindBarView(viewModel: viewModel) { [weak self] in
            self?.hideFindBar()
        }
        let host = NSHostingView(rootView: findView)
        findBarHost = host

        if let window = windowControllers.first?.window, let containerStack = window.contentView as? NSStackView {
            containerStack.insertView(host, at: 0, in: .top)
        }
    }

    private func hideFindBar() {
        if let host = findBarHost {
            host.removeFromSuperview()
            findBarHost = nil
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.state = (viewModel?.isGutterVisible == true) ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleSoftWrap(_:)) {
            menuItem.state = (viewModel?.isSoftWrapEnabled == true) ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleStatusBar(_:)) {
            menuItem.state = (viewModel?.isStatusBarVisible == true) ? .on : .off
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    /// One NSUndoManager registration per new UndoStack entry, replayed
    /// through the rope. `isUndoing` discriminates the redo direction;
    /// each replay re-registers so the chain continues both ways.
    @MainActor
    private func wireUndoCallback() {
        viewModel?.onNewUndoEntry = { [weak self] in
            self?.registerUndoReplay()
        }
    }

    @MainActor
    private func registerUndoReplay() {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                if document.undoManager?.isUndoing == true {
                    document.viewModel?.undo()
                } else {
                    document.viewModel?.redo()
                }
                document.registerUndoReplay()
            }
        }
    }
}
