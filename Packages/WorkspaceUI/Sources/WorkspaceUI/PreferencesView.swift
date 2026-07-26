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
                                TextField("Shortcut", text: $editingShortcutText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .multilineTextAlignment(.center)
                                Button("Save") {
                                    viewModel.setShortcut(editingShortcutText, for: actionID)
                                    editingActionID = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        } else {
                            Button {
                                editingActionID = actionID
                                editingShortcutText = viewModel.shortcut(for: actionID)
                            } label: {
                                KeycapBadgeView(shortcut: viewModel.shortcut(for: actionID))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
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

/// Renders a native macOS Keycap badge (e.g. ⌘ ⇧ F)
public struct KeycapBadgeView: View {
    let shortcut: String

    public init(shortcut: String) {
        self.shortcut = shortcut
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(keycapSymbols(for: shortcut), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
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

    private func keycapSymbols(for raw: String) -> [String] {
        guard !raw.isEmpty else { return ["None"] }
        let parts = raw.lowercased().components(separatedBy: "+")
        return parts.map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "shift": return "⇧"
            case "option", "alt": return "⌥"
            case "ctrl", "control": return "⌃"
            default: return part.uppercased()
            }
        }
    }
}
