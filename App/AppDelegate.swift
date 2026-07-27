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

    /// The single shared favourites store, constructed once at the
    /// composition root so all documents share the same ordered favourite
    /// list and sidebar updates propagate immediately across windows.
    @MainActor
    static let favoritesStore = FavoritesStore()

    /// The one shared Preferences window, created lazily on first use.
    @MainActor
    private lazy var preferencesWindowController = PreferencesWindowController(
        settingsStore: AppDelegate.settingsStore,
    )

    /// Window controller for the crash report dialog (if shown).
    @MainActor
    private var crashReportWindowController: CrashReportWindowController?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.build(settingsStore: AppDelegate.settingsStore)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.activate()
        let args = CommandLine.arguments
        let isTesting = isRunningUnderXCTest
        let didCrash = isTesting ? false : CrashDetector.checkAndMarkLaunch()

        if args.contains("--perf-cold-launch") {
            DispatchQueue.main.async {
                Swift.print("[MERIDIAN_PERF] FIRST_WINDOW_READY")
                fflush(stdout)
                exit(0)
            }
        } else {
            handleIdleTabsIfNeeded(args: args)
            handlePerfOpenIfNeeded(args: args)
            if didCrash {
                DispatchQueue.main.async { [weak self] in
                    let report = DiagnosticReportCollector.collectLatestReport()
                    let windowController = CrashReportWindowController(report: report)
                    self?.crashReportWindowController = windowController
                    windowController.show()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashDetector.markCleanShutdown()
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

    /// Perf harness hook: opens `path` and prints a timing marker once the
    /// document's text is actually on screen. Distinct from
    /// `--perf-idle-tabs` because it must survive an open failure and
    /// report it rather than hanging until the harness times out.
    @MainActor
    private func handlePerfOpenIfNeeded(args: [String]) {
        guard let idx = args.firstIndex(of: "--perf-open"), idx + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[idx + 1])
        let clock = ContinuousClock()
        let start = clock.now
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            MainActor.assumeIsolated {
                if let error {
                    Swift.print("[MERIDIAN_PERF] FILE_OPEN_FAILED \(error.localizedDescription)")
                    fflush(stdout)
                    return
                }
                // One turn of the run loop after the open callback: the
                // document is loaded, but the first layout pass has not
                // necessarily drawn. Measuring here matches "time to
                // visible text" in ROADMAP's budget table.
                DispatchQueue.main.async {
                    let elapsed = start.duration(to: clock.now)
                    let ms = Double(elapsed.components.seconds) * 1000
                        + Double(elapsed.components.attoseconds) / 1e15
                    Swift.print("[MERIDIAN_PERF] FILE_VISIBLE \(ms)")
                    fflush(stdout)
                }
            }
        }
    }

    @MainActor
    @objc func showPreferences(_ sender: Any?) {
        preferencesWindowController.show()
    }

    @MainActor
    @objc func showCommandPalette(_ sender: Any?) {
        if let doc = NSDocumentController.shared.currentDocument as? MeridianDocument {
            doc.showCommandPalette(sender)
        } else {
            do {
                if let doc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? MeridianDocument {
                    DispatchQueue.main.async {
                        doc.showCommandPalette(sender)
                    }
                }
            } catch {}
        }
    }

    @MainActor
    @objc func performFind(_ sender: Any?) {
        if let doc = NSDocumentController.shared.currentDocument as? MeridianDocument {
            doc.performFind(sender)
        } else {
            do {
                if let doc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? MeridianDocument {
                    DispatchQueue.main.async {
                        doc.performFind(sender)
                    }
                }
            } catch {}
        }
    }

    #if DEBUG
        @objc func simulateCrash(_ sender: Any?) {
            fatalError("Simulated crash for M5 Phase 3b test")
        }
    #endif

    private var isRunningUnderXCTest: Bool {
        let env = ProcessInfo.processInfo.environment
        if env.keys.contains(where: { $0.hasPrefix("XC") || $0.hasPrefix("XCTest") }) {
            return true
        }
        if env["DYLD_INSERT_LIBRARIES"]?.contains("XCTest") == true {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return false
    }

    /// Document-based default: launching (or clicking the Dock icon with
    /// no windows) opens an untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
