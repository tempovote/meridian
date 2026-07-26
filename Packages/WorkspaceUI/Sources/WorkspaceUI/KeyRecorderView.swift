import AppKit
import SwiftUI

/// An NSViewRepresentable that intercepts physical key combinations (e.g. Cmd+Shift+D, Cmd+F)
/// directly via AppKit NSEvent handling, preventing system menu shortcuts from swallowing them.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var shortcutText: String
    var onCancel: () -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onShortcutRecorded = { newShortcut in
            shortcutText = newShortcut
        }
        view.onCancel = {
            onCancel()
        }
        view.onSubmit = {
            onSubmit()
        }
        DispatchQueue.main.async {
            if let window = view.window {
                _ = window.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window, window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }
}

final class KeyRecorderNSView: NSView {
    var onShortcutRecorded: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKeyEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        _ = handleKeyEvent(event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Escape key -> cancel
        if keyCode == 53 {
            onCancel?()
            return true
        }

        // Return / Enter key -> submit
        if keyCode == 36 || keyCode == 76 {
            onSubmit?()
            return true
        }

        // Modifier-only key codes: 54, 55 (Cmd), 56, 60 (Shift), 58, 61 (Option), 59, 62 (Control), 63 (Fn)
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(keyCode) {
            return true
        }

        var parts: [String] = []
        if flags.contains(.command) {
            parts.append("cmd")
        }
        if flags.contains(.shift) {
            parts.append("shift")
        }
        if flags.contains(.option) {
            parts.append("option")
        }
        if flags.contains(.control) {
            parts.append("ctrl")
        }

        let keyString = mapKeyString(for: keyCode, event: event)
        if !keyString.isEmpty {
            parts.append(keyString)
            let result = parts.joined(separator: "+")
            onShortcutRecorded?(result)
            return true
        }

        return false
    }

    private static let specialKeyMap: [UInt16: String] = [
        48: "tab", 49: "space", 51: "delete",
        123: "left", 124: "right", 125: "down", 126: "up",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    private func mapKeyString(for keyCode: UInt16, event: NSEvent) -> String {
        if let mapped = Self.specialKeyMap[keyCode] {
            return mapped
        }
        if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
            return String(chars.first!)
        }
        return ""
    }
}
