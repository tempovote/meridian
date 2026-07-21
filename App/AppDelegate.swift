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
        let args = CommandLine.arguments
        if args.contains("--perf-cold-launch") {
            DispatchQueue.main.async {
                Swift.print("[MERIDIAN_PERF] FIRST_WINDOW_READY")
                fflush(stdout)
                exit(0)
            }
        } else {
            handleIdleTabsIfNeeded(args: args)
        }
    }

    @MainActor
    private func handleIdleTabsIfNeeded(args: [String]) {
        guard let idx = args.firstIndex(of: "--perf-idle-tabs"),
              idx + 1 < args.count,
              let tabCount = Int(args[idx + 1])
        else { return }
        DispatchQueue.main.async {
            let docController = NSDocumentController.shared
            let existingCount = docController.documents.count
            let needed = max(0, tabCount - existingCount)
            for _ in 0 ..< needed {
                try? docController.openUntitledDocumentAndDisplay(true)
            }
            Swift.print("[MERIDIAN_PERF] IDLE_TABS_READY")
            fflush(stdout)
        }
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
