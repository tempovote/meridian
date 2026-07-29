import FileKit
import Foundation
import Testing

@Suite("HexFormatterTests")
struct HexFormatterTests {
    @Test func formatEmptyData() {
        let rows = HexFormatter.format(data: Data())
        #expect(rows.isEmpty)
    }

    @Test func formatHelloWorld() {
        let data = Data("Hello World!".utf8)
        let rows = HexFormatter.format(data: data)
        #expect(rows.count == 1)
        #expect(rows[0].offsetString == "00000000")
        #expect(rows[0].ascii == "Hello World!")
        #expect(rows[0].hexBytes.contains("48 65 6C 6C 6F"))
    }

    @Test func formatMultipleRows() {
        var bytes: [UInt8] = Array(repeating: 0x41, count: 32) // 32 'A's
        bytes[31] = 0x0A // newline at byte 31
        let rows = HexFormatter.format(data: Data(bytes))
        #expect(rows.count == 2)
        #expect(rows[0].offsetString == "00000000")
        #expect(rows[1].offsetString == "00000010")
        #expect(rows[0].ascii == "AAAAAAAAAAAAAAAA")
        #expect(rows[1].ascii == "AAAAAAAAAAAAAAA.")
    }

    @Test func trailingPartialRowHoldsOnlyItsOwnBytes() {
        let data = Data(repeating: 0x41, count: 19)
        let rows = HexFormatter.format(data: data)
        #expect(rows.count == 2)
        #expect(rows[1].ascii == "AAA")
        #expect(rows[1].offsetString == "00000010")
    }

    @Test func nonPrintableBytesRenderAsDots() {
        let data = Data([0x00, 0x01, 0x1F, 0x7F, 0x41])
        let rows = HexFormatter.format(data: data)
        #expect(rows[0].ascii.hasSuffix("A"))
        #expect(rows[0].ascii.contains("."))
    }

    /// The offset column is fixed-width, so a file large enough to need more
    /// than four digits must not silently overflow the format or wrap to zero.
    @Test func offsetsPastFFFFAreFormattedWithEnoughDigits() {
        let data = Data(repeating: 0x41, count: 70000)
        let rows = HexFormatter.format(data: data)
        guard let last = rows.last else {
            Issue.record("no rows produced")
            return
        }
        #expect(last.offsetString.count >= 8)
        #expect(last.offsetString != "00000000")
        #expect(last.offset == (rows.count - 1) * 16)
    }

    /// Bytes above 0x7F are not ASCII and must render as dots rather than as
    /// whatever Latin-1 or a lossy UTF-8 decode would produce.
    @Test func highBitBytesAreNotRenderedAsGarbage() {
        let data = Data([0x80, 0xFF, 0xC3, 0xA9])
        let rows = HexFormatter.format(data: data)
        #expect(rows.count == 1)
        #expect(rows[0].hexBytes.contains("FF"))
        #expect(rows[0].ascii == "....")
    }

    @Test func customBytesPerRowIsHonoured() {
        let data = Data(repeating: 0x41, count: 16)
        let rows = HexFormatter.format(data: data, bytesPerRow: 8)
        #expect(rows.count == 2)
        #expect(rows[1].offset == 8)
    }
}
