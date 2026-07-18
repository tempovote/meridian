import AppKit
import DocumentCore
import EditorUI
import FileKit

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
            "This file is \(byteSize / (1024 * 1024)) MB. Files of 64 MB or more need huge-file mode, which arrives in a later release."
        case .lineTooLong:
            "This file contains an extremely long line, which this version cannot display safely. Support arrives with huge-file mode in a later release."
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
    /// Metadata from the loaded file (encoding/BOM for faithful save);
    /// nil for untitled documents (saved as UTF-8, no BOM, LF).
    private var loadedMetadata: (encoding: TextEncoding, hadBOM: Bool)?
    /// Buffer read before window controllers exist.
    private var pendingBuffer = TextBuffer()

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
            let engine = TextKit2Engine()
            let viewModel = EditorViewModel(buffer: pendingBuffer, engine: engine)
            self.engine = engine
            self.viewModel = viewModel
            wireUndoCallback()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false,
            )
            window.center()
            window.contentView = engine.view
            window.makeFirstResponder(engine.keyView)
            // Undo-routing gap confirmed empirically via EditorSmokeTests
            // (Cmd+Z was a silent no-op before this was wired): NSTextView
            // implements -undo:/-redo:/-undoManager itself and answers them
            // directly rather than forwarding up the responder chain
            // (allowsUndo = false only stops it from *auto-registering*
            // edits, not from intercepting the actions against its own
            // empty undo manager). Fixed by handing the document's undo
            // manager to the engine, which serves it via
            // NSTextViewDelegate.undoManager(for:).
            engine.documentUndoManager = undoManager
            addWindowController(NSWindowController(window: window))
        }
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
