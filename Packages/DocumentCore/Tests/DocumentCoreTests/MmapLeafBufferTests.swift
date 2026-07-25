import Foundation
import Testing
@testable import DocumentCore

@Suite("MmapLeafBufferTests")
struct MmapLeafBufferTests {
    @Test func mmapReadsSubrangeCorrectly() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.data")
        let content = "Hello World, MmapLeafBuffer Test!"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let buffer = try MmapLeafBuffer(url: file)
        #expect(buffer.fileSize == (content as NSString).length)

        let subBytes = buffer.bytes(in: 0 ..< 5)
        // swiftlint:disable:next optional_data_string_conversion
        let subString = String(decoding: subBytes, as: UTF8.self)
        #expect(subString == "Hello")

        let textBuffer = buffer.toTextBuffer()
        #expect(textBuffer.string == content)
    }

    @Test func textBufferInitWithFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("sample.txt")
        let content = "Sample file content for TextBuffer"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let textBuffer = try TextBuffer(contentsOfFile: file)
        #expect(textBuffer.string == content)
    }
}
