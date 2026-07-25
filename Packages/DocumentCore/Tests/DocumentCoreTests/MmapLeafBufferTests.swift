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

    @Test func textBufferInitWithMmapThresholdFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("large_mmap.txt")
        let chunk = String(repeating: "1234567890\n", count: 100_000) // 1.1 MB
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        // Write > 64 MB (exceeds 64 MB threshold)
        let chunkData = Data(chunk.utf8)
        for _ in 0 ..< 65 {
            try handle.write(contentsOf: chunkData)
        }

        let mmapBuffer = try MmapLeafBuffer(url: file)
        #expect(mmapBuffer.fileSize >= 64 * 1024 * 1024)

        let textBuffer = mmapBuffer.toTextBuffer()
        #expect(textBuffer.utf8Count == mmapBuffer.fileSize)
        #expect(textBuffer.lineCount > 5_000_000)
    }
}
