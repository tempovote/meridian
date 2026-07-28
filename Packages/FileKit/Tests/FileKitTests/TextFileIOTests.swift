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

    @Test func smallFileGetsNormalProfile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("small.txt")
        try Data("hello\nworld\n".utf8).write(to: url)

        let loaded = try TextFileIO.loadTextFile(at: url)
        #expect(loaded.profile.level == .normal)
        #expect(loaded.profile.capabilities.softWrap)
    }

    @Test func fileWithOneMillionByteLineGetsPathologicalProfile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("longline.txt")
        let line = String(repeating: "a", count: 1024 * 1024 + 10)
        try Data(line.utf8).write(to: url)

        let loaded = try TextFileIO.loadTextFile(at: url)
        #expect(loaded.profile.level == .pathologicalLines)
        #expect(!loaded.profile.capabilities.softWrap)
        #expect(loaded.profile.capabilities.syntaxHighlighting)
    }

    @Test func longestLineExcludesBreakBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("crlf.txt")
        try Data("abc\r\nde\r\n".utf8).write(to: url)

        let loaded = try TextFileIO.loadTextFile(at: url)
        #expect(loaded.longestLineUTF8Length == 3)
    }
}

@Suite("longestLineUTF8Length bounds")
struct LongestLineUTF8LengthBoundsTests {
    /// `scanAtMostBytes` must actually bound the scan: with the long line
    /// placed after the budget, a bounded call may never see it, while the
    /// unbounded call must. A no-op budget (one that silently scans
    /// everything) would make both calls agree and this test would fail.
    @Test func scanAtMostBytesStopsBeforeALaterLongLine() {
        let shortLines = String(repeating: "x\n", count: 2000) // 4000 bytes, each line length 1.
        let longLine = String(repeating: "y", count: 50)
        let buffer = TextBuffer(shortLines + longLine)

        let bounded = TextFileIO.longestLineUTF8Length(of: buffer, scanAtMostBytes: 1000)
        let unbounded = TextFileIO.longestLineUTF8Length(of: buffer)

        #expect(bounded == 1)
        #expect(unbounded == 50)
    }

    /// When the long line sits before the budget is spent, the bounded scan
    /// has already recorded it before it stops, so bounded and unbounded
    /// must agree.
    @Test func scanAtMostBytesAgreesWithUnboundedWhenLongLineIsEarly() {
        let longLine = String(repeating: "y", count: 50)
        let shortLines = String(repeating: "x\n", count: 2000) // 4000 bytes after the long line.
        let buffer = TextBuffer(longLine + "\n" + shortLines)

        let bounded = TextFileIO.longestLineUTF8Length(of: buffer, scanAtMostBytes: 3000)
        let unbounded = TextFileIO.longestLineUTF8Length(of: buffer)

        #expect(bounded == 50)
        #expect(unbounded == 50)
    }

    /// `stopOnceAtLeast` alone must stop as soon as a line reaches the
    /// threshold, never scanning on to find an even longer later line.
    @Test func stopOnceAtLeastDoesNotKeepScanningForALongerLine() {
        let earlyLine = String(repeating: "a", count: 100)
        let laterLongerLine = String(repeating: "b", count: 5000)
        let buffer = TextBuffer(earlyLine + "\n" + laterLongerLine)

        let result = TextFileIO.longestLineUTF8Length(of: buffer, stopOnceAtLeast: 50)

        #expect(result >= 50)
        #expect(result < 5000)
    }

    /// With both bounds absent, the scan is exact and unbounded even across
    /// many chunks — the small-file load path relies on this.
    @Test func bothBoundsNilYieldsTheExactValueAcrossManyChunks() {
        let head = String(repeating: "x\n", count: 1000) // 2000 bytes.
        let middle = String(repeating: "y", count: 10) // The true longest line.
        let tail = String(repeating: "z\n", count: 1000) // 2000 bytes.
        let buffer = TextBuffer(head + middle + "\n" + tail)

        #expect(TextFileIO.longestLineUTF8Length(of: buffer) == 10)
        #expect(TextFileIO.longestLineUTF8Length(of: buffer, stopOnceAtLeast: nil, scanAtMostBytes: nil) == 10)
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
