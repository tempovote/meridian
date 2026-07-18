import DocumentCore
import Foundation
import Testing
@testable import FileKit

@Suite("TextFileIO loading")
struct TextFileIOLoadTests {
    /// Creates a unique temp file containing `bytes`; caller's test dir is auto-deleted.
    private func writeTempFile(_ bytes: [UInt8]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("file.txt")
        try Data(bytes).write(to: url)
        return url
    }

    @Test func loadsUTF8WithMetadata() throws {
        let text = "alpha\nbeta xin chào\ngamma 🎉\n"
        let url = try writeTempFile(Array(text.utf8))
        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.buffer.string == text)
        #expect(file.encoding == .utf8)
        #expect(file.hadBOM == false)
        #expect(file.repairsMade == false)
        #expect(file.dominantLineEnding == .lf)
        #expect(file.byteSize == Array(text.utf8).count)
    }

    @Test func loadsUTF16LEWithBOM() throws {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for unit in "hi\r\nthere".utf16 {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        let url = try writeTempFile(bytes)
        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.buffer.string == "hi\r\nthere")
        #expect(file.encoding == .utf16LittleEndian)
        #expect(file.hadBOM == true)
        #expect(file.dominantLineEnding == .crlf)
    }

    @Test func longestLineMeasuredInUTF8Bytes() throws {
        // Line 2 is longest: "béta" = 5 UTF-8 bytes (é = 2 bytes).
        let url = try writeTempFile(Array("ab\nbéta\nc".utf8))
        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.longestLineUTF8Length == 5)
    }

    @Test func longestLineHandlesCRLFAndTrailingLine() throws {
        // CRLF must terminate a line (CR/LF bytes never count toward length);
        // the final unterminated line must still be measured.
        let url = try writeTempFile(Array("ab\r\ncdefgh".utf8))
        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.longestLineUTF8Length == 6)
    }

    @Test func emptyFileLoads() throws {
        let url = try writeTempFile([])
        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.buffer.isEmpty)
        #expect(file.longestLineUTF8Length == 0)
        #expect(file.dominantLineEnding == nil)
    }

    @Test func missingFileThrowsUnreadable() throws {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        #expect(throws: FileKitError.self) {
            _ = try TextFileIO.loadTextFile(at: url)
        }
    }
}

@Suite("TextFileIO saving")
struct TextFileIOSaveTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func roundTripsUTF8() throws {
        let url = try tempDir().appendingPathComponent("out.txt")
        let buffer = TextBuffer("xin chào 🎉\r\nline2\n")
        try TextFileIO.saveTextFile(buffer, as: .utf8, includeBOM: false, to: url)
        let reloaded = try TextFileIO.loadTextFile(at: url)
        #expect(reloaded.buffer.string == buffer.string)
        #expect(reloaded.encoding == .utf8)
        #expect(reloaded.hadBOM == false)
    }

    @Test func roundTripsUTF16BEWithBOM() throws {
        let url = try tempDir().appendingPathComponent("out.txt")
        let buffer = TextBuffer("ab\ncd")
        try TextFileIO.saveTextFile(buffer, as: .utf16BigEndian, includeBOM: true, to: url)
        let reloaded = try TextFileIO.loadTextFile(at: url)
        #expect(reloaded.buffer.string == "ab\ncd")
        #expect(reloaded.encoding == .utf16BigEndian)
        #expect(reloaded.hadBOM == true)
    }

    @Test func overwriteReplacesContent() throws {
        let url = try tempDir().appendingPathComponent("out.txt")
        try TextFileIO.saveTextFile(TextBuffer("old"), as: .utf8, includeBOM: false, to: url)
        try TextFileIO.saveTextFile(TextBuffer("new"), as: .utf8, includeBOM: false, to: url)
        #expect(try TextFileIO.loadTextFile(at: url).buffer.string == "new")
    }

    @Test func lossyLegacyEncodingThrowsUnencodable() throws {
        let url = try tempDir().appendingPathComponent("out.txt")
        // ASCII cannot represent "é" — encode must refuse, not corrupt.
        #expect(throws: FileKitError.self) {
            try TextFileIO.saveTextFile(
                TextBuffer("café"), as: .legacy(.ascii), includeBOM: false, to: url,
            )
        }
    }

    @Test func unwritableDirectoryThrowsUnwritable() throws {
        let url = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/out.txt")
        #expect(throws: FileKitError.self) {
            try TextFileIO.saveTextFile(TextBuffer("x"), as: .utf8, includeBOM: false, to: url)
        }
    }
}
