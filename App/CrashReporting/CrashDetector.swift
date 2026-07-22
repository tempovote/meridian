import Foundation

/// Handles tracking application shutdown state to detect unexpected terminations (crashes).
@MainActor
final class CrashDetector {
    private static let cleanShutdownKey = "MeridianCleanShutdown"

    /// Checks if the previous app instance crashed or terminated unexpectedly,
    /// and resets the flag for the current session.
    ///
    /// - Returns: `true` if the previous session exited unexpectedly (cleanShutdown == false).
    static func checkAndMarkLaunch() -> Bool {
        let defaults = UserDefaults.standard
        let previousShutdownState = defaults.object(forKey: cleanShutdownKey) as? Bool

        // If previousShutdownState is nil, this is the very first run ever -> not a crash.
        let crashed = (previousShutdownState == false)

        // Mark current session as running (not yet cleanly shutdown)
        defaults.set(false, forKey: cleanShutdownKey)
        defaults.synchronize()

        return crashed
    }

    /// Marks the current session as having cleanly shut down.
    static func markCleanShutdown() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: cleanShutdownKey)
        defaults.synchronize()
    }
}
