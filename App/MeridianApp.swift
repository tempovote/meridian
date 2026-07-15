import SwiftUI

@main
struct MeridianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Document windows arrive in M3 via NSDocument (ARCHITECTURE.md §5.2).
        Settings {
            Text("Meridian")
                .padding()
        }
    }
}
