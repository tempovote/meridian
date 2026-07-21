import Testing
@testable import ThemeKit

@Suite("HexColorTests")
struct HexColorTests {
    @Test func parsesValidHexWithHash() {
        let color = HexColor.nsColor(fromHex: "#FF00FF")
        #expect(color != nil)
        #expect(color?.redComponent == 1.0)
        #expect(color?.greenComponent == 0.0)
        #expect(color?.blueComponent == 1.0)
    }

    @Test func parsesValidHexWithoutHash() {
        let color = HexColor.nsColor(fromHex: "00FF00")
        #expect(color?.redComponent == 0.0)
        #expect(color?.greenComponent == 1.0)
        #expect(color?.blueComponent == 0.0)
    }

    @Test func rejectsInvalidLength() {
        #expect(HexColor.nsColor(fromHex: "#FFF") == nil)
        #expect(HexColor.nsColor(fromHex: "#FFFFFFF") == nil)
    }

    @Test func rejectsNonHexCharacters() {
        #expect(HexColor.nsColor(fromHex: "#GGGGGG") == nil)
    }
}
