import AppKit
import SearchKit
import SwiftUI

/// Window controller that presents the DiffView in a native macOS window.
@MainActor
public final class DiffWindowController: NSWindowController {
    public convenience init(diffResult: DiffResult) {
        let diffView = DiffView(result: diffResult)
        let hostingController = NSHostingController(rootView: diffView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Diff Viewer — \(diffResult.leftName) vs \(diffResult.rightName)"
        window.contentViewController = hostingController
        window.center()
        self.init(window: window)
    }
}
