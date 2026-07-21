import Foundation

/// Owns the current ``Settings``, persists them to
/// `settings.json`, and live-reloads on external edits (via
/// ``SettingsFileWatcher``, wired up in Task 3). The only write path is
/// ``update(_:)`` — it always produces valid JSON, so the malformed-file
/// error banner (``lastLoadError``) can only ever be set by an *external*
/// edit, never by this app's own Preferences UI.
@MainActor
public final class SettingsStore {
    public private(set) var current: Settings
    public private(set) var lastLoadError: SettingsKitError?

    private let fileURL: URL
    /// Top-level JSON keys this version of the app doesn't understand,
    /// preserved verbatim across load → update → save so an older app
    /// version editing settings.json never destroys a newer version's
    /// additive fields (ARCHITECTURE §14 forward compat).
    private var extraTopLevelJSON: [String: Any] = [:]
    private var changeHandlers: [(Settings) -> Void] = []
    private var watcher: SettingsFileWatcher?

    /// `~/Library/Application Support/Meridian/` when unsandboxed. The app
    /// build has `com.apple.security.app-sandbox` enabled, so this API
    /// (correctly) resolves to the sandbox container instead —
    /// `~/Library/Containers/<bundle-id>/Data/Library/Application Support/Meridian/`
    /// — for manual inspection/hand-editing during testing, look there,
    /// not the literal unsandboxed path.
    public static var defaultDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Meridian", isDirectory: true)
    }

    public init(directoryURL: URL = SettingsStore.defaultDirectory) {
        fileURL = directoryURL.appendingPathComponent("settings.json")
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            // Best-effort: if the directory truly can't be created, the
            // first `update(_:)` call surfaces a `.writeFailed` instead of
            // failing silently here.
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let loaded = try Self.load(from: fileURL)
                current = loaded.settings
                extraTopLevelJSON = loaded.extraTopLevelJSON
            } catch let error as SettingsKitError {
                current = .default
                lastLoadError = error
            } catch {
                current = .default
                lastLoadError = .decodingFailed(underlying: error)
            }
        } else {
            current = .default
        }
        watcher = SettingsFileWatcher(directoryURL: directoryURL) { [weak self] in
            assert(Thread.isMainThread, "SettingsFileWatcher fired off the main queue")
            MainActor.assumeIsolated {
                self?.reloadFromDisk()
            }
        }
    }

    /// The only write path: Preferences UI mutates a copy, this persists
    /// it and (on success) swaps it in as `current`. Notifies observers
    /// on both success AND failure — a subscriber (e.g. Preferences'
    /// error banner) needs to learn about a new `lastLoadError` just as
    /// much as it needs to learn about a new `current`.
    public func update(_ transform: (inout Settings) -> Void) {
        var next = current
        transform(&next)
        do {
            try persist(next)
            current = next
            lastLoadError = nil
        } catch let error as SettingsKitError {
            lastLoadError = error
        } catch {
            lastLoadError = .writeFailed(underlying: error)
        }
        notifyObservers()
    }

    /// Registers a handler fired after every `update` or external reload
    /// attempt, successful or not. Handlers are never removed for the
    /// lifetime of the app (P1 simplification — see plan Task 6 notes);
    /// each closure should capture its owner weakly.
    public func onChange(_ handler: @escaping (Settings) -> Void) {
        changeHandlers.append(handler)
    }

    /// Called by ``SettingsFileWatcher`` (Task 3) when `settings.json`'s
    /// directory changes. A no-op if the file doesn't currently exist
    /// (some other file in the directory changed, or `settings.json` was
    /// deleted) — that is not an error, just nothing to reload. Notifies
    /// observers on both success AND failure (see `update(_:)`'s doc
    /// comment for why) — this is the path a hand-edited, broken
    /// `settings.json` takes, and without notifying on failure too, an
    /// already-open Preferences window's error banner would never learn
    /// that `lastLoadError` just changed.
    func reloadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let loaded = try Self.load(from: fileURL)
            current = loaded.settings
            extraTopLevelJSON = loaded.extraTopLevelJSON
            lastLoadError = nil
        } catch let error as SettingsKitError {
            lastLoadError = error
        } catch {
            lastLoadError = .decodingFailed(underlying: error)
        }
        notifyObservers()
    }

    private func notifyObservers() {
        for handler in changeHandlers {
            handler(current)
        }
    }

    private static func load(
        from url: URL,
    ) throws -> (settings: Settings, extraTopLevelJSON: [String: Any]) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsKitError.decodingFailed(underlying: error)
        }
        let settings: Settings
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            throw SettingsKitError.decodingFailed(underlying: error)
        }
        var raw: [String: Any]
        do {
            raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw SettingsKitError.decodingFailed(underlying: error)
        }
        raw.removeValue(forKey: "schemaVersion")
        raw.removeValue(forKey: "editor")
        return (settings, raw)
    }

    private func persist(_ settings: Settings) throws {
        var raw = extraTopLevelJSON
        raw["schemaVersion"] = settings.schemaVersion
        let editorData: Data
        do {
            editorData = try JSONEncoder().encode(settings.editor)
            raw["editor"] = try JSONSerialization.jsonObject(with: editorData)
        } catch {
            throw SettingsKitError.writeFailed(underlying: error)
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw SettingsKitError.writeFailed(underlying: error)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SettingsKitError.writeFailed(underlying: error)
        }
    }
}
