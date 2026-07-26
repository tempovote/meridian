import SettingsKit
import SwiftUI

public struct PreferencesView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case editor = "Editor"
        case keybindings = "Keybindings"

        public var id: String {
            rawValue
        }
    }

    @Bindable var viewModel: PreferencesViewModel
    @State private var selectedTab: Tab = .editor

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
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal], 16)

            switch selectedTab {
            case .editor:
                editorForm
            case .keybindings:
                keybindingsForm
            }
        }
        .frame(width: 460, height: 380)
    }

    private var editorForm: some View {
        Form {
            Picker("Font Family", selection: $viewModel.fontFamily) {
                ForEach(MonospacedFontFamilies.installed, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(
                "Font Size: \(Int(viewModel.fontSize))",
                value: $viewModel.fontSize, in: 9 ... 24, step: 1,
            )
            Stepper("Tab Width: \(viewModel.tabWidth)", value: $viewModel.tabWidth, in: 1 ... 8)
            Toggle("Soft Wrap by Default", isOn: $viewModel.softWrapDefault)
        }
        .padding(20)
    }

    private var keybindingsForm: some View {
        VStack(spacing: 12) {
            List {
                ForEach(Array(KeybindingSettings.defaultShortcuts.keys.sorted()), id: \.self) { actionID in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(actionDisplayName(actionID))
                                .font(.body)
                                .fontWeight(.medium)
                            Text(actionID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        let currentSc = viewModel.shortcut(for: actionID)
                        TextField(
                            "Shortcut",
                            text: Binding(
                                get: { currentSc },
                                set: { newValue in viewModel.setShortcut(newValue, for: actionID) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Spacer()
                Button("Reset Keybindings to Defaults") {
                    viewModel.resetKeybindingsToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding([.horizontal, .bottom], 16)
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
