import DocumentCore
import Foundation
import SearchKit
import Testing

@Suite("FindInFilesEngineTests")
struct FindInFilesEngineTests {
    @Test func searchFindsMatchesInTemporaryDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("file1.swift")
        let file2 = tempDir.appendingPathComponent("file2.txt")
        let file3 = tempDir.appendingPathComponent("ignored.png")

        try "func testMeridian() {\n    print(\"Hello Meridian\")\n}\n".write(
            to: file1,
            atomically: true,
            encoding: .utf8,
        )
        try "Meridian text editor\nanother line\n".write(to: file2, atomically: true, encoding: .utf8)
        try "binary data".write(to: file3, atomically: true, encoding: .utf8)

        let engine = FindInFilesEngine()
        let query = FindInFilesQuery(
            query: "Meridian",
            searchFolder: tempDir,
            options: [.caseSensitive],
            includePattern: "",
            excludePattern: "*.png",
        )

        let results = await engine.search(query: query)
        #expect(results.count == 2)

        let totalMatches = results.flatMap(\.matches)
        #expect(totalMatches.count == 3)
    }

    @Test func searchRespectsIncludePatterns() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("code.swift")
        let file2 = tempDir.appendingPathComponent("notes.md")

        try "target text in swift\n".write(to: file1, atomically: true, encoding: .utf8)
        try "target text in md\n".write(to: file2, atomically: true, encoding: .utf8)

        let engine = FindInFilesEngine()
        let query = FindInFilesQuery(
            query: "target",
            searchFolder: tempDir,
            includePattern: "*.swift",
        )

        let results = await engine.search(query: query)
        #expect(results.count == 1)
        #expect(results[0].fileURL.lastPathComponent == "code.swift")
    }
}
