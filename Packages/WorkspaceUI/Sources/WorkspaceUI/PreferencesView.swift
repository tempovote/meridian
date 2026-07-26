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
                                // Keycap badge display with invisible input capture on top
                                ZStack {
                                    // Visual layer: live keycap badges
                                    Group {
                                        if editingShortcutText.isEmpty {
                                            Text("Type shortcut…")
                                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        } else {
                                            KeycapBadgeView(shortcut: editingShortcutText)
                                        }
                                    }
                                    .allowsHitTesting(false)

                                    // Input layer: invisible but focusable NSTextField
                                    SingleLineTextField(
                                        text: $editingShortcutText,
                                        placeholder: "",
                                        autoFocus: true,
                                        onSubmit: {
                                            viewModel.setShortcut(editingShortcutText, for: actionID)
                                            editingActionID = nil
                                        },
                                    )
                                    .opacity(0.001)
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

// MARK: - SingleLineTextField

/// A truly single-line NSTextField wrapper that prevents text from wrapping outside its frame.
/// SwiftUI's built-in TextField on macOS does not respect lineLimit(1) at the NSTextField level,
/// causing the text to render below the frame bounds. This view fixes that.
struct SingleLineTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var autoFocus: Bool
    var onSubmit: () -> Void

    init(
        text: Binding<String>,
        placeholder: String = "",
        autoFocus: Bool = false,
        onSubmit: @escaping () -> Void,
    ) {
        _text = text
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        field.alignment = .center
        // Force true single-line behaviour at the AppKit level
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        if autoFocus {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SingleLineTextField

        init(_ parent: SingleLineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector,
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
