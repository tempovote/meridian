import Foundation

/// Typed errors for SettingsKit. Both are reachable at runtime (unlike
/// ThemeKit's bundled-resource errors) — a user can hand-edit
/// `settings.json` into something invalid, or the app-support directory
/// can become unwritable (disk full, permissions).
public enum SettingsKitError: Error, LocalizedError {
    case decodingFailed(underlying: Error)
    case writeFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case let .decodingFailed(underlying):
            "settings.json couldn't be read: \(underlying.localizedDescription) — using previous settings."
        case let .writeFailed(underlying):
            "settings.json couldn't be saved: \(underlying.localizedDescription)."
        }
    }
}
