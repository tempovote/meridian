import AppKit

/// Service managing application auto-updates and release checks for Meridian.
@MainActor
public final class UpdaterService: NSObject {
    public static let shared = UpdaterService()

    public func checkForUpdates() {
        // Auto-update framework entry point (Sparkle / Release check)
    }
}
