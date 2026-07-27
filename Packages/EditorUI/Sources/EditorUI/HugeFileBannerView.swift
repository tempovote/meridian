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
    private let effectiveCapabilities: HugeFileProfile.Capabilities
    private let hasOverriddenCapabilities: Bool
    private let onOverride: () -> Void
    private let onDismiss: () -> Void
    @State private var isConfirmingOverride = false

    /// Creates the banner for the given restriction `profile`.
    /// `effectiveCapabilities` and `hasOverriddenCapabilities` describe
    /// what is ACTUALLY in force right now, which can differ from
    /// `profile.capabilities` once the user has confirmed "Enable
    /// Anyway" — the banner's copy and controls key off those, not off
    /// `profile` directly, so it never claims a feature is off after it
    /// has been turned back on. `onOverride` is called only after the
    /// user confirms the "Enable Anyway" dialog; `onDismiss` is called
    /// directly from the close button.
    public init(
        profile: HugeFileProfile,
        effectiveCapabilities: HugeFileProfile.Capabilities,
        hasOverriddenCapabilities: Bool,
        onOverride: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
    ) {
        self.profile = profile
        self.effectiveCapabilities = effectiveCapabilities
        self.hasOverriddenCapabilities = hasOverriddenCapabilities
        self.onOverride = onOverride
        self.onDismiss = onDismiss
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(profile.byteSize), countStyle: .file)
    }

    /// After an override, the original per-tier headline ("Huge file
    /// mode…" / "Long-line mode…") would misleadingly suggest nothing
    /// has changed — swap in copy naming what actually remains
    /// restricted instead.
    private var headline: String {
        guard !hasOverriddenCapabilities else {
            return "Heavy features enabled — \(sizeText)"
        }
        switch profile.level {
        case .normal: return ""
        case .huge: return "Huge file mode — \(sizeText)"
        case .pathologicalLines:
            return "Long-line mode — longest line is \(profile.longestLineUTF8Length / (1024 * 1024)) MB"
        }
    }

    private var subtext: String {
        let names = effectiveCapabilities.disabledFeatureNames.joined(separator: ", ")
        return hasOverriddenCapabilities ? "Still off: \(names)" : "Turned off: \(names)"
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.system(size: 12, weight: .semibold))
                Text(subtext)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Once heavy features are already on, offering "Enable
            // Anyway" again is meaningless — soft wrap is the one
            // capability that never comes back (see `effectiveCapabilities`'s
            // doc comment), so there is nothing left to confirm.
            if !hasOverriddenCapabilities {
                Button("Enable Anyway") { isConfirmingOverride = true }
                    .controlSize(.small)
            }
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
