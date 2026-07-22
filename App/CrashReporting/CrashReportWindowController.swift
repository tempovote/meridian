import AppKit
import SwiftUI

/// AppKit WindowController for hosting `CrashReportView`.
@MainActor
final class CrashReportWindowController: NSWindowController {
    init(report: DiagnosticReport) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Meridian Crash Diagnostics"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let rootView = CrashReportView(report: report) { [weak self] in
            self?.close()
        }
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
