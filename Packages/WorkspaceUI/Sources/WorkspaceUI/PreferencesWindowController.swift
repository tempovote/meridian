import AppKit
import SettingsKit
import SwiftUI

/// One shared Preferences window per app (Cmd+,). The composition root
/// (`AppDelegate`) owns the single instance and calls `show()` to reuse
/// and refront it rather than creating a second window.
@MainActor
public final class PreferencesWindowController: NSWindowController {
    public init(settingsStore: SettingsStore) {
        let viewModel = PreferencesViewModel(store: settingsStore)
        let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Preferences"
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
