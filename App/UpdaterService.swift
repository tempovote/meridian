import AppKit
import Sparkle

/// Service managing application auto-updates via the Sparkle 2 framework.
///
/// Wraps `SPUStandardUpdaterController`, which:
/// - Schedules a background update check on launch (configurable via `SUScheduledCheckInterval`).
/// - Presents Sparkle's native update UI when an update is found.
/// - Uses XPC services for sandbox-safe installation.
///
/// The app's `Info.plist` must contain:
/// - `SUFeedURL`      — the appcast URL.
/// - `SUPublicEDKey`  — the base64 EdDSA public key for signature verification.
/// - `SUEnableInstallerLauncherService` — required for sandboxed apps.
@MainActor
public final class UpdaterService: NSObject {
    /// The single shared instance.
    public static let shared = UpdaterService()

    /// The Sparkle controller that owns the updater lifecycle.
    ///
    /// Keeping a strong reference here prevents ARC from deallocating
    /// the updater between checks.
    private let updaterController: SPUStandardUpdaterController

    override private init() {
        // `startingUpdater: true` lets Sparkle schedule its initial
        // background check automatically on the next run loop tick.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )
        super.init()
    }

    /// Presents Sparkle's standard "Check for Updates" sheet.
    ///
    /// Called by `AppDelegate → checkForUpdates:` menu action
    /// and by `MeridianDocument → checkForUpdates:`.
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether a user-initiated check can be made right now.
    ///
    /// Use this in `validateMenuItem` to enable/disable the
    /// "Check for Updates…" menu item correctly.
    public var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
