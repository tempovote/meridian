import SwiftUI

/// The Preferences window's sole content (P1 has exactly one settings
/// category, "Editor" — see plan/spec Non-Goals for the toolbar-tabs
/// deferral). Every field writes through immediately via `viewModel`'s
/// property setters.
public struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel

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
        .frame(width: 360)
    }
}
