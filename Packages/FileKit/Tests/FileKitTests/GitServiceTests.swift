import FileKit
import Foundation
import Testing

@Suite("GitServiceTests")
struct GitServiceTests {
    /// A fresh temp directory, removed when the test returns.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-gitservice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A file that lives outside any git repository has no version history to
    /// diff against, so it must show no marks at all. It used to come back
    /// with every line marked `.added` — the fallback meant for a genuinely
    /// new file inside a repository — painting a solid green bar down the
    /// whole gutter for any file opened from a non-repo directory.
    @Test func fileOutsideAnyRepositoryHasNoMarks() async throws {
        try await withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("sample.swift")
            let text = "let a = 1\nlet b = 2\nlet c = 3\n"
            try text.write(to: fileURL, atomically: true, encoding: .utf8)

            let marks = await GitService.shared.diffStatus(bufferText: text, fileURL: fileURL)
            #expect(marks.isEmpty)
        }
    }

    /// The counterpart the fallback exists for: inside a repository, a file
    /// git has never seen really is all new.
    @Test func untrackedFileInsideRepositoryIsAllAdded() async throws {
        try await withTemporaryDirectory { directory in
            try git(["init", "--initial-branch=main"], in: directory)
            let fileURL = directory.appendingPathComponent("sample.swift")
            let text = "let a = 1\nlet b = 2\nlet c = 3\n"
            try text.write(to: fileURL, atomically: true, encoding: .utf8)

            let marks = await GitService.shared.diffStatus(bufferText: text, fileURL: fileURL)
            #expect(marks[0] == .added)
            #expect(marks[1] == .added)
            #expect(marks[2] == .added)
        }
    }

    @Test func parseAdditionHunk() {
        let diff = """
        @@ -0,0 +1,3 @@
        +line 1
        +line 2
        +line 3
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[0] == .added)
        #expect(marks[1] == .added)
        #expect(marks[2] == .added)
    }

    @Test func parseModificationHunk() {
        let diff = """
        @@ -10,2 +10,2 @@
        -old line
        +new line
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[9] == .modified)
        #expect(marks[10] == .modified)
    }

    @Test func parseDeletionHunk() {
        let diff = """
        @@ -15,2 +15,0 @@
        -deleted line 1
        -deleted line 2
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[14] == .deleted)
    }

    @Test func parseMixedHunks() {
        let diff = """
        @@ -5,1 +5,1 @@
        -old
        +new
        @@ -20,0 +21,2 @@
        +added 1
        +added 2
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[4] == .modified)
        #expect(marks[20] == .added)
        #expect(marks[21] == .added)
    }
}
