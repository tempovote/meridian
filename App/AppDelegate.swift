import AppKit
import ThemeKit

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

    /// Document-based default: launching (or clicking the Dock icon with
    /// no windows) opens an untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
