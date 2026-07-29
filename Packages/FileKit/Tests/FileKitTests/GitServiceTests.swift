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

    /// Initialises a repository in `directory` with `file.txt` committed.
    private func makeRepo(in directory: URL, contents: String = "alpha\nbeta\n") throws {
        try git(["init", "--initial-branch=main"], in: directory)
        try git(["config", "user.email", "test@example.com"], in: directory)
        try git(["config", "user.name", "Test"], in: directory)
        try Data(contents.utf8).write(to: directory.appendingPathComponent("file.txt"))
        try git(["add", "file.txt"], in: directory)
        try git(["commit", "-q", "-m", "initial"], in: directory)
    }

    @Test func committedFileWithNoEditsHasNoMarks() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let marks = await GitService.shared.diffStatus(for: directory.appendingPathComponent("file.txt"))
            #expect(marks.isEmpty)
        }
    }

    @Test func modifiedFileOnDiskReportsMarks() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let fileURL = directory.appendingPathComponent("file.txt")
            try Data("alpha\nCHANGED\n".utf8).write(to: fileURL)

            let marks = await GitService.shared.diffStatus(for: fileURL)
            #expect(!marks.isEmpty)
            #expect(marks.values.contains { $0 == .modified || $0 == .added })
        }
    }

    /// A repository that has been `git init`-ed but never committed has no
    /// HEAD to compare against, so every line is genuinely new — the same
    /// answer as an untracked file, and for the same reason. Asserted rather
    /// than assumed because `rev-parse --show-prefix` *succeeds* here, so
    /// this does not take the "not in a repository" path.
    @Test func repositoryWithNoCommitsMarksEveryLineAdded() async throws {
        try await withTemporaryDirectory { directory in
            try git(["init", "--initial-branch=main"], in: directory)
            let fileURL = directory.appendingPathComponent("file.txt")
            let text = "one\ntwo\n"
            try Data(text.utf8).write(to: fileURL)

            let marks = await GitService.shared.diffStatus(bufferText: text, fileURL: fileURL)
            #expect(marks[0] == .added)
            #expect(marks[1] == .added)
        }
    }

    /// Arguments are passed to `Process` as an array, so a space in a name is
    /// only safe because nothing builds a shell command string. This pins it.
    @Test func fileNameContainingSpacesIsHandled() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let spaced = directory.appendingPathComponent("file with spaces.txt")
            try Data("x\n".utf8).write(to: spaced)
            try git(["add", "file with spaces.txt"], in: directory)
            try git(["commit", "-q", "-m", "spaced"], in: directory)
            try Data("y\n".utf8).write(to: spaced)

            let marks = await GitService.shared.diffStatus(for: spaced)
            #expect(!marks.isEmpty)
        }
    }

    /// Exercises the `--show-prefix` branch: for a file below the repository
    /// root the path handed to `git show HEAD:` must carry the prefix, or the
    /// lookup fails and the gutter silently falls back to marking everything
    /// added.
    @Test func fileInSubdirectoryResolvesAgainstRepositoryRoot() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let subdirectory = directory.appendingPathComponent("sub", isDirectory: true)
            try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
            let nested = subdirectory.appendingPathComponent("nested.txt")
            try Data("one\ntwo\n".utf8).write(to: nested)
            try git(["add", "sub/nested.txt"], in: directory)
            try git(["commit", "-q", "-m", "nested"], in: directory)

            // Committed and unedited: an all-added result here would mean the
            // prefix was lost and HEAD lookup failed.
            let marks = await GitService.shared.diffStatus(bufferText: "one\ntwo\n", fileURL: nested)
            #expect(marks.isEmpty)
        }
    }

    @Test func deletedFileReturnsWithoutCrashing() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let fileURL = directory.appendingPathComponent("file.txt")
            try FileManager.default.removeItem(at: fileURL)
            _ = await GitService.shared.diffStatus(for: fileURL)
        }
    }

    /// The path the gutter actually uses while typing: nothing is written to
    /// disk, so the diff has to come from the in-memory text.
    @Test func inMemoryBufferDiffersFromCommittedContent() async throws {
        try await withTemporaryDirectory { directory in
            try makeRepo(in: directory)
            let fileURL = directory.appendingPathComponent("file.txt")

            let marks = await GitService.shared.diffStatus(
                bufferText: "alpha\nEDITED IN MEMORY\n", fileURL: fileURL,
            )
            #expect(!marks.isEmpty)
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
