import FileKit
import Testing

@Suite("HugeFileProfileTests")
struct HugeFileProfileTests {
    @Test func smallFileEnablesEverything() {
        let profile = HugeFileProfile(byteSize: 1024, longestLineUTF8Length: 80)
        #expect(profile.level == .normal)
        #expect(profile.capabilities.syntaxHighlighting)
        #expect(profile.capabilities.folding)
        #expect(profile.capabilities.minimap)
        #expect(profile.capabilities.gitGutter)
        #expect(profile.capabilities.bracketMatching)
        #expect(profile.capabilities.softWrap)
        #expect(profile.capabilities.findInFiles)
    }

    @Test func oneByteBelowThresholdIsStillNormal() {
        let profile = HugeFileProfile(byteSize: 64 * 1024 * 1024 - 1, longestLineUTF8Length: 80)
        #expect(profile.level == .normal)
    }

    @Test func exactlyAtThresholdIsHuge() {
        let profile = HugeFileProfile(byteSize: 64 * 1024 * 1024, longestLineUTF8Length: 80)
        #expect(profile.level == .huge)
    }

    @Test func hugeFileDisablesWholeFileScanFeatures() {
        let profile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(!profile.capabilities.syntaxHighlighting)
        #expect(!profile.capabilities.folding)
        #expect(!profile.capabilities.minimap)
        #expect(!profile.capabilities.gitGutter)
        #expect(!profile.capabilities.bracketMatching)
        #expect(!profile.capabilities.softWrap)
    }

    @Test func hugeFileKeepsFindInFiles() {
        // Search streams over the rope and never materializes the document,
        // so it survives huge mode. Losing find on a 1 GB log would defeat
        // the point of opening it.
        let profile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(profile.capabilities.findInFiles)
    }

    @Test func smallFileWithLongLineForbidsSoftWrapOnly() {
        let profile = HugeFileProfile(byteSize: 2 * 1024 * 1024, longestLineUTF8Length: 2 * 1024 * 1024)
        #expect(profile.level == .pathologicalLines)
        #expect(!profile.capabilities.softWrap)
        #expect(profile.capabilities.syntaxHighlighting)
        #expect(profile.capabilities.minimap)
    }

    @Test func oneByteBelowLineThresholdKeepsSoftWrap() {
        let profile = HugeFileProfile(byteSize: 2 * 1024 * 1024, longestLineUTF8Length: 1024 * 1024 - 1)
        #expect(profile.level == .normal)
        #expect(profile.capabilities.softWrap)
    }

    @Test func exactlyAtLineThresholdIsPathological() {
        let profile = HugeFileProfile(byteSize: 2 * 1024 * 1024, longestLineUTF8Length: 1024 * 1024)
        #expect(profile.level == .pathologicalLines)
        #expect(!profile.capabilities.softWrap)
    }

    @Test func hugeAndPathologicalCapabilitiesMatchPlainHuge() {
        // The point of this test is the equality assertion below, not the individual
        // flags: a huge+pathological file's capabilities must be byte-for-byte identical
        // to a plain huge file's, because every restriction the pathological-line rule
        // imposes is already imposed by the huge-size rule. A `switch level` design has
        // a distinct `.huge` case it could (incorrectly) special-case differently when a
        // pathological line is also present; computing each flag independently from
        // `isHuge`/`hasPathologicalLine`, as the real implementation does, cannot drift
        // from plain huge in that way. This guards the per-capability design, not any
        // one flag's value.
        let hugeAndPathological = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 50_000_000)
        let plainHuge = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        #expect(hugeAndPathological.level == .huge)
        #expect(hugeAndPathological.capabilities == plainHuge.capabilities)
        #expect(!hugeAndPathological.capabilities.syntaxHighlighting)
        #expect(!hugeAndPathological.capabilities.folding)
        #expect(!hugeAndPathological.capabilities.minimap)
        #expect(!hugeAndPathological.capabilities.gitGutter)
        #expect(!hugeAndPathological.capabilities.bracketMatching)
        #expect(!hugeAndPathological.capabilities.softWrap)
        #expect(hugeAndPathological.capabilities.findInFiles)
    }

    @Test func disabledFeatureNamesAreHumanReadable() {
        let profile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 80)
        let names = profile.disabledFeatureNames
        #expect(names.contains("Syntax highlighting"))
        #expect(names.contains("Soft wrap"))
        #expect(!names.contains("Find in files"))
    }

    @Test func normalFileHasNoDisabledFeatureNames() {
        let profile = HugeFileProfile(byteSize: 1024, longestLineUTF8Length: 80)
        #expect(profile.disabledFeatureNames.isEmpty)
    }
}
