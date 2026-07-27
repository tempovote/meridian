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

    @Test func hugeAndPathologicalTakesUnionOfRestrictions() {
        let profile = HugeFileProfile(byteSize: 1_000_000_000, longestLineUTF8Length: 50_000_000)
        #expect(profile.level == .huge)
        #expect(!profile.capabilities.softWrap)
        #expect(!profile.capabilities.syntaxHighlighting)
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
