import Foundation

/// Watches a directory (not `settings.json` itself — the file may not
/// exist yet, and atomic writes via `Data.write(options: .atomic)`
/// replace the inode, which a file-descriptor watch on the file itself
/// would silently stop following) for changes, firing `onChange` for
/// every directory-content event. Not actor-isolated — it's a thin GCD
/// wrapper; the caller's `onChange` closure is responsible for bridging
/// back to whatever actor it needs (see `SettingsStore`'s use of it).
final class SettingsFileWatcher {
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32

    /// `nil` if the directory couldn't be opened for watching (e.g. it
    /// doesn't exist) — `SettingsStore` treats a `nil` watcher as
    /// "live reload unavailable this session," not a fatal error.
    init?(directoryURL: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        descriptor = fd
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend, .delete],
            queue: .main,
        )
        source.setEventHandler(handler: onChange)
        let capturedDescriptor = fd
        source.setCancelHandler {
            close(capturedDescriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
