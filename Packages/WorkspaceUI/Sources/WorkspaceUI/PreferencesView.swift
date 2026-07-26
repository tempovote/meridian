import SettingsKit
import SwiftUI

public struct PreferencesView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case editor = "Editor"
        case keybindings = "Keybindings"

        public var id: String {
            rawValue
        }

        public var icon: String {
            switch self {
            case .editor: "text.alignleft"
            case .keybindings: "keyboard"
            }
        }
    }

    @Bindable var viewModel: PreferencesViewModel
    @State private var selectedTab: Tab = .editor
    @State private var searchText = ""
    @State private var editingActionID: String?
    @State private var editingShortcutText = ""

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let bannerMessage = viewModel.bannerMessage {
                Text(bannerMessage)
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
            }

            // Native Segmented Control Header
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .padding(.vertical, 12)

            Divider()

            switch selectedTab {
            case .editor:
                editorTab
            case .keybindings:
                keybindingsTab
            }
        }
        .frame(width: 500, height: 420)
    }

    private var editorTab: some View {
        Form {
            Section("Typography") {
                Picker("Font Family", selection: $viewModel.fontFamily) {
                    ForEach(MonospacedFontFamilies.installed, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(
                    "Font Size: \(Int(viewModel.fontSize)) pt",
                    value: $viewModel.fontSize, in: 9 ... 24, step: 1,
                )
            }

            Section("Editor Behavior") {
                Stepper("Tab Width: \(viewModel.tabWidth) spaces", value: $viewModel.tabWidth, in: 1 ... 8)
                Toggle("Soft Wrap by Default", isOn: $viewModel.softWrapDefault)
            }
        }
        .formStyle(.grouped)
    }

    private var keybindingsTab: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search Shortcuts...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Customizable Keybindings") {
                ForEach(filteredActionIDs, id: \.self) { actionID in
                    HStack {
                        Text(actionDisplayName(actionID))
                            .font(.body)
                            .fontWeight(.medium)

                        Spacer()

                        if editingActionID == actionID {
                            HStack(spacing: 6) {
                                // Keycap badge display with key recorder on top
                                ZStack {
                                    // Visual layer: live keycap badges
                                    Group {
                                        if editingShortcutText.isEmpty {
                                            Text("Press keys…")
                                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        } else {
                                            KeycapBadgeView(shortcut: editingShortcutText)
                                        }
                                    }
                                    .allowsHitTesting(false)

                                    // Input layer: AppKit KeyRecorderNSView capturing key events
                                    KeyRecorderView(
                                        shortcutText: $editingShortcutText,
                                        onCancel: {
                                            editingActionID = nil
                                        },
                                        onSubmit: {
                                            viewModel.setShortcut(editingShortcutText, for: actionID)
                                            editingActionID = nil
                                        },
                                    )
                                }
                                .frame(minWidth: 80, maxWidth: 160)
                                .frame(height: 28)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.controlBackgroundColor)),
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.accentColor, lineWidth: 1.5),
                                )

                                Button {
                                    viewModel.setShortcut(editingShortcutText, for: actionID)
                                    editingActionID = nil
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 17))
                                }
                                .buttonStyle(.plain)
                                .help("Save Shortcut")

                                Button {
                                    editingActionID = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                        .font(.system(size: 17))
                                }
                                .buttonStyle(.plain)
                                .help("Cancel")
                            }
                        } else {
                            Button {
                                editingActionID = actionID
                                editingShortcutText = viewModel.shortcut(for: actionID)
                            } label: {
                                KeycapBadgeView(shortcut: viewModel.shortcut(for: actionID))
                            }
                            .buttonStyle(.plain)
                            .help("Click to edit shortcut")
                        }
                    }
                    .frame(height: 28)
                }
            }

            Section {
                Button("Reset Keybindings to Defaults") {
                    viewModel.resetKeybindingsToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
    }

    private var filteredActionIDs: [String] {
        let keys = KeybindingSettings.defaultShortcuts.keys.sorted()
        if searchText.isEmpty {
            return keys
        }
        return keys.filter { actionID in
            actionID.localizedCaseInsensitiveContains(searchText) ||
                actionDisplayName(actionID).localizedCaseInsensitiveContains(searchText)
        }
    }

    private func actionDisplayName(_ actionID: String) -> String {
        switch actionID {
        case "find": "Find"
        case "findInFiles": "Find in Files"
        case "formatDocument": "Format Document"
        case "toggleMarkdownPreview": "Toggle Markdown Preview"
        case "foldAll": "Fold All"
        case "unfoldAll": "Unfold All"
        case "toggleSoftWrap": "Toggle Soft Wrap"
        case "duplicateLine": "Duplicate Line"
        default: actionID
        }
    }
}

/// Renders native macOS Keycap badges (e.g. ⌘ ⇧ F)
public struct KeycapBadgeView: View {
    let shortcut: String

    public init(shortcut: String) {
        self.shortcut = shortcut
    }

    public var body: some View {
        let symbols = keycapSymbols(for: shortcut)
        HStack(spacing: 3) {
            if symbols.isEmpty {
                Text("None")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1),
                    )
            } else {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1),
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1),
                        )
                }
            }
        }
    }

    private func keycapSymbols(for raw: String) -> [String] {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let parts = raw.lowercased().components(separatedBy: "+").filter { !$0.isEmpty }
        return parts.map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "shift": return "⇧"
            case "option", "alt": return "⌥"
            case "ctrl", "control": return "⌃"
            case "return", "enter": return "↩"
            case "delete", "backspace": return "⌫"
            case "escape", "esc": return "⎋"
            case "tab": return "⇥"
            case "space": return "Space"
            case "left": return "←"
            case "right": return "→"
            case "up": return "↑"
            case "down": return "↓"
            default: return part.uppercased()
            }
        }
    }
}

// MARK: - KeyRecorderView

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
        return handleKeyEvent(event)
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

        // Modifiers
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

        // Modifier-only key codes: 54, 55 (Cmd), 56, 60 (Shift), 58, 61 (Option), 59, 62 (Control), 63 (Fn)
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(keyCode) {
            return true
        }

        // Key character mapping
        let keyString = switch keyCode {
        case 48: "tab"
        case 49: "space"
        case 51: "delete"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 23: "5"
        case 22: "6"
        case 26: "7"
        case 28: "8"
        case 25: "9"
        case 29: "0"
        case 27: "-"
        case 24: "="
        case 33: "["
        case 30: "]"
        case 42: "\\"
        case 41: ";"
        case 39: "'"
        case 43: ","
        case 47: "."
        case 44: "/"
        case 50: "`"
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
                String(chars.first!)
            } else {
                ""
            }
        }

        if !keyString.isEmpty {
            parts.append(keyString)
            let result = parts.joined(separator: "+")
            onShortcutRecorded?(result)
            return true
        }

        return false
    }
}
