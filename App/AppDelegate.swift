import AppKit
import SettingsKit
import ThemeKit
import WorkspaceUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The single shared theme engine, constructed once at the
    /// composition root (CLAUDE.md's sole permitted singleton exception)
    /// so every open document/window resolves colors from the same live
    /// theme state and repaints together on a system appearance change.
    /// "Auto" pairs Meridian Dark/Meridian Light per ARCHITECTURE §13;
    /// the two "Contrast" bundled themes aren't reachable without a
    /// picker UI yet (M4 Phase 3 design decision 1 — deferred to M5).
    @MainActor
    static let themeEngine = ThemeEngine(
        darkTheme: BundledThemes.meridianDark,
        lightTheme: BundledThemes.meridianLight,
    )

    /// The single shared settings store, constructed once at the
    /// composition root alongside `themeEngine` (both are the same
    /// sanctioned "no singletons except the composition root" exception —
    /// `AppDelegate` *is* the composition root).
    @MainActor
    static let settingsStore = SettingsStore()

    /// The one shared Preferences window, created lazily on first use.
    @MainActor
    private lazy var preferencesWindowController = PreferencesWindowController(
        settingsStore: AppDelegate.settingsStore,
    )

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.build()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    @MainActor
    @objc func showPreferences(_ sender: Any?) {
        preferencesWindowController.show()
    }

    /// Document-based default: launching (or clicking the Dock icon with
    /// no windows) opens an untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
