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

    /// Calculates line-by-line git diff marks for the file at `fileURL` relative to git HEAD.
    /// Returns a map of 0-based line indices to `GitGutterMark`.
    public func diffStatus(for fileURL: URL) async -> [Int: GitGutterMark] {
        let path = fileURL.path
        let directory = fileURL.deletingLastPathComponent().path

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
}
