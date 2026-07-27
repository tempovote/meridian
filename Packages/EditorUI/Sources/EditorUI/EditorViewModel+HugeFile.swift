import FileKit

/// Huge-file capability gating: which whole-file-scan features
/// ``EditorViewModel/hugeFileProfile`` currently permits, and the one
/// user action (``EditorViewModel/overrideCapabilities()``) that can
/// widen that set. Split from `EditorViewModel.swift` to keep that
/// file's primary declaration within the project's type-body-length
/// budget — the same convention `TextKit2Engine+*.swift` already uses.
public extension EditorViewModel {
    /// Whether the huge-file banner should currently be shown: there is
    /// something STILL restricted in ``effectiveCapabilities`` — not just
    /// in the original ``hugeFileProfile`` — and the user hasn't dismissed
    /// it. Consulting `effectiveCapabilities` rather than `hugeFileProfile`
    /// directly is what makes the banner keep tracking reality after
    /// ``overrideCapabilities()``: for a huge (not pathological-line) file
    /// with every capability restored except soft wrap, this stays `true`
    /// (there is still something to explain — see `HugeFileBannerView`'s
    /// override-aware copy) instead of continuing to report the pre-override
    /// five-feature list, or vanishing and leaving the still-disabled soft
    /// wrap toggle unexplained.
    var isHugeFileBannerVisible: Bool {
        !effectiveCapabilities.disabledFeatureNames.isEmpty && !isBannerDismissed
    }

    /// Whether the user has explicitly re-enabled heavy features via
    /// ``overrideCapabilities()``. Read-only outside the module — exposed
    /// so callers such as the huge-file banner can adapt their copy after
    /// an override without needing write access to the underlying flag.
    var hasEnabledHeavyFeatureOverride: Bool {
        hasOverriddenCapabilities
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
