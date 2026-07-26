import AppKit
import Sparkle

/// Service managing application auto-updates via the Sparkle 2 framework.
///
/// Wraps `SPUStandardUpdaterController`, which:
/// - Schedules a background update check on launch (configurable via `SUScheduledCheckInterval`).
/// - Presents Sparkle's native update UI when an update is found.
/// - Uses XPC services for sandbox-safe installation.
///
/// Under UI test runs (XCTest), updater initialization is skipped so headless
/// test runners with ad-hoc signatures do not fail on Sparkle XPC Mach lookups.
@MainActor
public final class UpdaterService: NSObject {
    /// The single shared instance.
    public static let shared = UpdaterService()

    /// The Sparkle controller that owns the updater lifecycle (nil when running under XCTest).
    private let updaterController: SPUStandardUpdaterController?

    override private init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil

        if isTesting {
            updaterController = nil
        } else {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil,
            )
        }
        super.init()
    }

    /// Presents Sparkle's standard "Check for Updates" sheet.
    public func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Whether a user-initiated check can be made right now.
    public var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }
}
