import Foundation

/// Represents the Git change status for a 0-based line index in a file.
public enum GitGutterMark: String, Sendable, Equatable {
    case none
    case added
    case modified
    case deleted
}

/// Asynchronous service that shells out to system `git` to calculate line-by-line diff status.
public actor GitService {
    public static let shared = GitService()

    public init() {}

    /// The file's path relative to its repository root, or `nil` when
    /// `directory` is not inside a git work tree at all.
    ///
    /// The `nil` case must stay distinguishable from "in a repository, but
    /// git has never seen this file": the latter is legitimately all-new
    /// content, the former has no history to compare against and so has no
    /// marks to show. Collapsing the two painted the whole gutter green for
    /// every file opened from a non-repo directory.
    private func repositoryRelativePath(fileURL: URL, directory: String) -> String? {
        let fileName = fileURL.lastPathComponent
        let rootProcess = Process()
        rootProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        rootProcess.arguments = ["rev-parse", "--show-prefix"]
        rootProcess.currentDirectoryURL = URL(fileURLWithPath: directory)

        let rootPipe = Pipe()
        rootProcess.standardOutput = rootPipe
        rootProcess.standardError = Pipe()

        do {
            try rootProcess.run()
            rootProcess.waitUntilExit()
            guard rootProcess.terminationStatus == 0 else { return nil }
            let data = rootPipe.fileHandleForReading.readDataToEndOfFile()
            let rawPrefix = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return rawPrefix.isEmpty ? fileName : rawPrefix + fileName
        } catch {
            return nil
        }
    }

    private func fetchHeadText(relativePath: String, directory: String) async -> String? {
        let showProcess = Process()
        showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        showProcess.arguments = ["show", "HEAD:\(relativePath)"]
        showProcess.currentDirectoryURL = URL(fileURLWithPath: directory)

        let showPipe = Pipe()
        showProcess.standardOutput = showPipe
        showProcess.standardError = Pipe()

        do {
            try showProcess.run()
            showProcess.waitUntilExit()
            if showProcess.terminationStatus == 0 {
                let data = showPipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
        } catch {}
        return nil
    }

    private func isIgnored(fileURL: URL, directory: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["check-ignore", "-q", "--", fileURL.path]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Calculates line-by-line git diff marks for `bufferText` relative to git HEAD at `fileURL`.
    /// Works for both saved and unsaved in-memory edits.
    public func diffStatus(bufferText: String, fileURL: URL) async -> [Int: GitGutterMark] {
        let directory = fileURL.deletingLastPathComponent().path
        guard let relativePath = repositoryRelativePath(fileURL: fileURL, directory: directory) else {
            // Not version-controlled at all — nothing to diff, no marks.
            return [:]
        }
        if isIgnored(fileURL: fileURL, directory: directory) {
            // Ignored by git (e.g. .git/info/exclude, .gitignore) — no marks.
            return [:]
        }
        guard let headText = await fetchHeadText(relativePath: relativePath, directory: directory) else {
            let diskMarks = await diffStatus(for: fileURL)
            if !diskMarks.isEmpty {
                return diskMarks
            }
            var marks: [Int: GitGutterMark] = [:]
            let lines = bufferText.components(separatedBy: .newlines)
            for lineIndex in 0 ..< lines.count {
                marks[lineIndex] = .added
            }
            return marks
        }

        // 3. Diff headText vs in-memory bufferText using temp files
        let tempDir = FileManager.default.temporaryDirectory
        let headFileURL = tempDir.appendingPathComponent("meridian_head_\(UUID().uuidString)")
        let bufferFileURL = tempDir.appendingPathComponent("meridian_buf_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: headFileURL)
            try? FileManager.default.removeItem(at: bufferFileURL)
        }

        do {
            try headText.write(to: headFileURL, atomically: true, encoding: .utf8)
            try bufferText.write(to: bufferFileURL, atomically: true, encoding: .utf8)

            let diffProcess = Process()
            diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            diffProcess.arguments = ["diff", "-U0", "--no-color", "--no-index", headFileURL.path, bufferFileURL.path]

            let diffPipe = Pipe()
            diffProcess.standardOutput = diffPipe
            diffProcess.standardError = Pipe()

            try diffProcess.run()
            diffProcess.waitUntilExit()

            let diffData = diffPipe.fileHandleForReading.readDataToEndOfFile()
            guard let diffOutput = String(data: diffData, encoding: .utf8) else { return [:] }
            return Self.parseHunks(diffOutput: diffOutput)
        } catch {
            return [:]
        }
    }

    /// Calculates line-by-line git diff marks for the file at `fileURL` relative to git HEAD on disk.
    public func diffStatus(for fileURL: URL) async -> [Int: GitGutterMark] {
        let path = fileURL.path
        let directory = fileURL.deletingLastPathComponent().path
        if isIgnored(fileURL: fileURL, directory: directory) {
            return [:]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "-U0", "--no-color", "--", path]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            guard let diffOutput = String(data: data, encoding: .utf8) else { return [:] }
            return Self.parseHunks(diffOutput: diffOutput)
        } catch {
            return [:]
        }
    }

    /// Parses unified diff hunks (e.g. `@@ -oldLine,oldCount +newLine,newCount @@`)
    /// into a map of 0-based line index to `GitGutterMark`.
    public static func parseHunks(diffOutput: String) -> [Int: GitGutterMark] {
        var result: [Int: GitGutterMark] = [:]
        let lines = diffOutput.components(separatedBy: .newlines)

        for line in lines {
            guard line.hasPrefix("@@ ") else { continue }
            let components = line.components(separatedBy: " ")
            guard components.count >= 3 else { continue }

            let oldPart = components[1]
            let newPart = components[2]

            guard oldPart.hasPrefix("-"), newPart.hasPrefix("+") else { continue }

            let oldRange = parseHunkRange(String(oldPart.dropFirst()))
            let newRange = parseHunkRange(String(newPart.dropFirst()))

            _ = oldRange.line
            let oldCount = oldRange.count
            let newStart = newRange.line
            let newCount = newRange.count

            if oldCount == 0, newCount > 0 {
                let startLine = max(0, newStart - 1)
                for lineIndex in startLine ..< (startLine + newCount) {
                    result[lineIndex] = .added
                }
            } else if oldCount > 0, newCount == 0 {
                let deletedAtLine = max(0, newStart - 1)
                result[deletedAtLine] = .deleted
            } else if oldCount > 0, newCount > 0 {
                let startLine = max(0, newStart - 1)
                for lineIndex in startLine ..< (startLine + newCount) {
                    result[lineIndex] = .modified
                }
            }
        }
        return result
    }

    private static func parseHunkRange(_ string: String) -> (line: Int, count: Int) {
        let parts = string.components(separatedBy: ",")
        let line = Int(parts[0]) ?? 0
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (line, count)
    }

    /// Returns current Git branch name for `directory`, or `nil` if not inside a git worktree.
    public func currentBranch(in directory: URL) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name != "HEAD" else { return nil }
            return name
        } catch {
            return nil
        }
    }
}
