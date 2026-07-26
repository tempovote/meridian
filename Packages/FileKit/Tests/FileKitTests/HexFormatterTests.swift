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
}
