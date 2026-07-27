import FileKit

/// Huge-file capability gating: which whole-file-scan features
/// ``EditorViewModel/hugeFileProfile`` currently permits, and the one
/// user action (``EditorViewModel/overrideCapabilities()``) that can
/// widen that set. Split from `EditorViewModel.swift` to keep that
/// file's primary declaration within the project's type-body-length
/// budget — the same convention `TextKit2Engine+*.swift` already uses.
public extension EditorViewModel {
    /// Whether the huge-file banner should currently be shown: there is
    /// something to warn about and the user hasn't dismissed it.
    var isHugeFileBannerVisible: Bool {
        hugeFileProfile.level != .normal && !isBannerDismissed
    }

    /// The capabilities actually in force, after any user override.
    var effectiveCapabilities: HugeFileProfile.Capabilities {
        guard hasOverriddenCapabilities else { return hugeFileProfile.capabilities }
        return HugeFileProfile.Capabilities(
            syntaxHighlighting: true,
            folding: true,
            minimap: true,
            gitGutter: true,
            bracketMatching: true,
            // Never restored: soft wrap over a multi-megabyte line is the
            // one setting that can wedge layout badly enough that the user
            // cannot get back out of it (ADR 0009's 11 GB measurement).
            softWrap: hugeFileProfile.capabilities.softWrap,
            findInFiles: true,
        )
    }

    /// Turns the heavy features back on for a user who has accepted the
    /// cost. Callers must have confirmed with the user first.
    func overrideCapabilities() {
        hasOverriddenCapabilities = true
        engine.profile = hugeFileProfile
        engine.capabilitiesOverride = effectiveCapabilities
    }

    /// Copies `other`'s size-restriction state onto `self`: profile,
    /// override acceptance, and banner dismissal. Used when a new pane is
    /// created alongside `other` (a split's secondary pane) — plain
    /// `hugeFileProfile = other.hugeFileProfile` is not enough, because
    /// that property's own `didSet` unconditionally resets
    /// `hasOverriddenCapabilities`/`isBannerDismissed`, which would
    /// silently discard an already-accepted "Enable Anyway" override on
    /// the new pane. Callers should still set the new pane's engine's
    /// `profile` themselves before constructing its `EditorViewModel` —
    /// this method only fixes up the view-model-side state once the pane
    /// already exists, same as `hugeFileProfile`'s own assignment.
    func inheritHugeFileState(from other: EditorViewModel) {
        hugeFileProfile = other.hugeFileProfile
        isBannerDismissed = other.isBannerDismissed
        if other.hasOverriddenCapabilities {
            overrideCapabilities()
        }
    }
}

extension EditorViewModel {
    /// Re-clamps display state to whatever `hugeFileProfile` currently
    /// allows and re-arms the engine's gate. Called from
    /// `hugeFileProfile`'s `didSet` in `EditorViewModel.swift`.
    func clampCapabilities() {
        if !hugeFileProfile.capabilities.softWrap {
            isSoftWrapEnabled = false
        }
        engine.profile = hugeFileProfile
        engine.capabilitiesOverride = nil
    }
}
