import FileKit
import SwiftUI

/// Non-modal bar explaining why the editor has switched features off.
///
/// Silently degrading would read as a broken app, so the banner names the
/// file size, lists what is off, and offers a way back — behind a
/// confirmation, because re-enabling a whole-file parse on a gigabyte file
/// is a decision the user should make deliberately.
public struct HugeFileBannerView: View {
    private let profile: HugeFileProfile
    private let onOverride: () -> Void
    private let onDismiss: () -> Void
    @State private var isConfirmingOverride = false

    /// Creates the banner for the given restriction `profile`. `onOverride`
    /// is called only after the user confirms the "Enable Anyway" dialog;
    /// `onDismiss` is called directly from the close button.
    public init(
        profile: HugeFileProfile,
        onOverride: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
    ) {
        self.profile = profile
        self.onOverride = onOverride
        self.onDismiss = onDismiss
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(profile.byteSize), countStyle: .file)
    }

    private var headline: String {
        switch profile.level {
        case .normal: ""
        case .huge: "Huge file mode — \(sizeText)"
        case .pathologicalLines: "Long-line mode — longest line is \(profile.longestLineUTF8Length / (1024 * 1024)) MB"
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.system(size: 12, weight: .semibold))
                Text("Turned off: \(profile.disabledFeatureNames.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Enable Anyway") { isConfirmingOverride = true }
                .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .confirmationDialog(
            "Enable all features on a \(sizeText) file?",
            isPresented: $isConfirmingOverride,
            titleVisibility: .visible,
        ) {
            Button("Enable Anyway", role: .destructive, action: onOverride)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Syntax highlighting and the minimap scan the whole file. On a file this size "
                    + "the app may become unresponsive or run out of memory.",
            )
        }
    }
}
