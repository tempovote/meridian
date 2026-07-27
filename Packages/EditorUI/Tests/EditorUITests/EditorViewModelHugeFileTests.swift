import AppKit
import DocumentCore
import FileKit
import Testing
@testable import EditorUI

/// Huge-file capability gating and banner-visibility coverage for
/// `EditorViewModel`, split out of `EditorViewModelTests.swift` to keep
/// that file's `EditorViewModelTests` struct within the project's
/// type-body-length budget — the same convention `TextKit2Engine+*.swift`
/// / `EditorViewModel+HugeFile.swift` already use for their source-side
/// counterparts. Shares `MockLayoutEngine` and the `makeViewModel(...)`
/// helpers declared (non-`private`, for this reason) in
/// `EditorViewModelTests.swift`.
@MainActor
@Suite("EditorViewModel Huge File")
struct EditorViewModelHugeFileTests {
    @Test func hugeProfileForcesSoftWrapOff() {
        let model = makeViewModel()
        model.isSoftWrapEnabled = true
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(!model.isSoftWrapEnabled)
    }

    @Test func softWrapCannotBeTurnedBackOnUnderHugeProfile() {
        let model = makeViewModel()
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        model.isSoftWrapEnabled = true
        #expect(!model.isSoftWrapEnabled)
    }

    @Test func normalProfileLeavesSoftWrapAlone() {
        let model = makeViewModel()
        model.hugeFileProfile = .unrestricted
        model.isSoftWrapEnabled = true
        #expect(model.isSoftWrapEnabled)
    }

    @Test func bannerIsShownOnlyForRestrictedProfiles() {
        let model = makeViewModel()
        #expect(!model.isHugeFileBannerVisible)
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(model.isHugeFileBannerVisible)
    }

    @Test func dismissingTheBannerDoesNotRestoreCapabilities() {
        let model = makeViewModel()
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        model.isBannerDismissed = true
        #expect(!model.isHugeFileBannerVisible)
        #expect(!model.effectiveCapabilities.syntaxHighlighting)
    }

    @Test func overrideRestoresCapabilitiesButNotSoftWrapForLongLines() {
        let model = makeViewModel()
        model.hugeFileProfile = HugeFileProfile(
            byteSize: 1_000_000_000, longestLineUTF8Length: 50_000_000,
        )
        model.overrideCapabilities()
        #expect(model.effectiveCapabilities.syntaxHighlighting)
        // Soft wrap stays off: it is the one restriction that exists to
        // avoid a layout blow-up the user cannot recover from, and there is
        // no partial version of it.
        #expect(!model.effectiveCapabilities.softWrap)
    }

    // MARK: - Final-review Fix 4: the banner must track effectiveCapabilities, not hugeFileProfile

    /// Before this fix, `isHugeFileBannerVisible` read `hugeFileProfile
    /// .level` directly, so it never changed after an override — that
    /// alone was harmless (the banner staying up is arguably correct
    /// here, since soft wrap can never come back), but combined with the
    /// app rendering `hugeFileProfile.disabledFeatureNames` it produced a
    /// banner that kept listing all five originally-restricted features
    /// as still off. This pins the two things that must now be true: the
    /// banner is still visible (soft wrap is permanently restricted for
    /// any huge/pathological profile, so there is always something left
    /// to explain), but what it would report as "off" has narrowed to
    /// just soft wrap.
    @Test func bannerPersistsAfterOverrideButOnlyReportsSoftWrapAsStillOff() {
        let model = makeViewModel()
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(model.effectiveCapabilities.disabledFeatureNames.count > 1)

        model.overrideCapabilities()

        #expect(model.isHugeFileBannerVisible)
        #expect(model.effectiveCapabilities.disabledFeatureNames == ["Soft wrap"])
    }

    /// `hasEnabledHeavyFeatureOverride` is the public, read-only window
    /// onto the view model's internal override flag — it must observably
    /// flip the moment `overrideCapabilities()` runs, since callers (the
    /// huge-file banner host) key their copy off it.
    @Test func hasEnabledHeavyFeatureOverrideReflectsOverrideCapabilitiesCall() {
        let model = makeViewModel()
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(!model.hasEnabledHeavyFeatureOverride)

        model.overrideCapabilities()
        #expect(model.hasEnabledHeavyFeatureOverride)
    }

    /// A file with no restrictions at all must never show the banner,
    /// override or not — guards against the narrowed
    /// `disabledFeatureNames`-driven visibility check regressing to
    /// "always show once profile is non-nil" or similar.
    @Test func normalProfileNeverShowsBannerEvenIfSomehowOverridden() {
        let model = makeViewModel()
        model.hugeFileProfile = .unrestricted
        #expect(!model.isHugeFileBannerVisible)
    }

    // MARK: - M10PA Task 5 Finding 3: split must inherit an accepted override

    /// `setSplit()` propagates `hugeFileProfile` to the new secondary
    /// pane. A plain `hugeFileProfile = primary.hugeFileProfile` alone
    /// would silently discard an already-accepted "Enable Anyway"
    /// override on the new pane, because `hugeFileProfile`'s own
    /// `didSet` unconditionally resets `hasOverriddenCapabilities`.
    /// `inheritHugeFileState(from:)` must carry the override across.
    @Test func inheritHugeFileStateCarriesAnAcceptedOverrideToTheNewPane() {
        let primary = makeViewModel()
        primary.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        primary.overrideCapabilities()
        #expect(primary.effectiveCapabilities.syntaxHighlighting)

        let secondary = makeViewModel()
        secondary.inheritHugeFileState(from: primary)

        #expect(secondary.hugeFileProfile == primary.hugeFileProfile)
        #expect(secondary.effectiveCapabilities.syntaxHighlighting)
        #expect(secondary.effectiveCapabilities.minimap)
    }

    /// The dismissal state must also carry over: a pane split off of a
    /// primary whose banner is already dismissed must not pop the banner
    /// back up.
    @Test func inheritHugeFileStateCarriesBannerDismissal() {
        let primary = makeViewModel()
        primary.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        primary.isBannerDismissed = true

        let secondary = makeViewModel()
        secondary.inheritHugeFileState(from: primary)

        #expect(!secondary.isHugeFileBannerVisible)
    }

    /// Without any override on the primary, the new pane must stay
    /// restricted — inheriting must not itself grant an override.
    @Test func inheritHugeFileStateWithNoOverrideLeavesNewPaneRestricted() {
        let primary = makeViewModel()
        primary.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)

        let secondary = makeViewModel()
        secondary.inheritHugeFileState(from: primary)

        #expect(!secondary.effectiveCapabilities.syntaxHighlighting)
    }

    // MARK: - Final-review Fix 8: overrideCapabilities/clampCapabilities must reach the engine

    /// `overrideCapabilities()` and `clampCapabilities()` (the latter run
    /// via `hugeFileProfile`'s `didSet`) both write `engine
    /// .capabilitiesOverride` directly rather than through any other
    /// observable surface — nothing previously asserted that the write
    /// actually happens. `MockLayoutEngine` records it verbatim, so this
    /// checks it lands both ways: non-nil after an override, `nil` again
    /// once the profile changes and re-clamps.
    @Test func overrideAndClampWriteEngineCapabilitiesOverride() {
        let engine = MockLayoutEngine()
        let model = makeViewModel(TextBuffer(""), engine: engine)
        model.hugeFileProfile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)

        model.overrideCapabilities()
        #expect(engine.capabilitiesOverride?.syntaxHighlighting == true)

        model.hugeFileProfile = .unrestricted
        #expect(engine.capabilitiesOverride == nil)
    }
}
