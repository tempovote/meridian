import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
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
