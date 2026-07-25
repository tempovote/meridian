import DocumentCore
import FileKit
import Foundation

/// Represents a single match inside a file found during workspace search.
public struct FileMatch: Equatable, Sendable, Identifiable {
    public var id: String {
        "\(line):\(column):\(range.lowerBound.value)"
    }

    /// 1-based line number.
    public let line: Int
    /// 1-based column number (in UTF-16 code units).
    public let column: Int
    /// Byte range of the match within the file's text buffer.
    public let range: Range<ByteOffset>
    /// Preview snippet of the line containing the match.
    public let lineSnippet: String

    public init(line: Int, column: Int, range: Range<ByteOffset>, lineSnippet: String) {
        self.line = line
        self.column = column
        self.range = range
        self.lineSnippet = lineSnippet
    }
}

/// Search results grouped by file URL.
public struct FileSearchResult: Equatable, Sendable, Identifiable {
    public var id: String {
        fileURL.path
    }

    public let fileURL: URL
    public let matches: [FileMatch]

    public init(fileURL: URL, matches: [FileMatch]) {
        self.fileURL = fileURL
        self.matches = matches
    }
}

/// Query parameters for Find in Files workspace search.
public struct FindInFilesQuery: Equatable, Sendable {
    public var query: String
    public var replacement: String
    public var searchFolder: URL?
    public var options: SearchOptions
    public var includePattern: String
    public var excludePattern: String

    public init(
        query: String = "",
        replacement: String = "",
        searchFolder: URL? = nil,
        options: SearchOptions = [],
        includePattern: String = "",
        excludePattern: String = "",
    ) {
        self.query = query
        self.replacement = replacement
        self.searchFolder = searchFolder
        self.options = options
        self.includePattern = includePattern
        self.excludePattern = excludePattern
    }
}

/// Asynchronous search engine for searching across all files in a folder or workspace.
public final class FindInFilesEngine: Sendable {
    public init() {}

    /// Performs an asynchronous search across files under `query.searchFolder`.
    public func search(query: FindInFilesQuery, maxTotalMatches: Int = 1000) async -> [FileSearchResult] {
        guard !query.query.isEmpty, let folder = query.searchFolder else { return [] }

        let searchEngine = SearchEngine()
        let includes = parsePatterns(query.includePattern)
        let excludes = parsePatterns(query.excludePattern)

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else { return [] }

        var results: [FileSearchResult] = []
        var totalMatchesCount = 0

        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
        for fileURL in fileURLs {
            if Task.isCancelled || totalMatchesCount >= maxTotalMatches {
                break
            }

            if shouldSkipFile(fileURL, includes: includes, excludes: excludes) {
                continue
            }

            let maxRemaining = maxTotalMatches - totalMatchesCount
            let fileMatches = processFile(
                fileURL: fileURL,
                query: query,
                searchEngine: searchEngine,
                maxMatches: maxRemaining,
            )
            if !fileMatches.isEmpty {
                totalMatchesCount += fileMatches.count
                results.append(FileSearchResult(fileURL: fileURL, matches: fileMatches))
            }
        }

        return results
    }

    /// Replaces all occurrences found in `results` with `query.replacement`.
    /// Returns the total count of matches replaced across all files.
    @discardableResult
    public func replaceAll(query: FindInFilesQuery, results: [FileSearchResult]) async -> Int {
        guard !query.query.isEmpty, !results.isEmpty else { return 0 }
        let searchEngine = SearchEngine()
        var totalReplaced = 0

        for result in results {
            if Task.isCancelled {
                break
            }
            guard let loaded = try? TextFileIO.loadTextFile(at: result.fileURL) else { continue }
            var buffer = loaded.buffer
            let matches = searchEngine.findAll(query: query.query, in: buffer, options: query.options)
            guard !matches.isEmpty else { continue }

            let transaction = searchEngine.buildReplaceTransaction(
                matches: matches,
                replacement: query.replacement,
                in: buffer,
            )
            buffer.apply(transaction)

            do {
                try TextFileIO.saveTextFile(
                    buffer,
                    as: loaded.encoding,
                    includeBOM: loaded.hadBOM,
                    to: result.fileURL,
                )
                totalReplaced += matches.count
            } catch {
                continue
            }
        }

        return totalReplaced
    }

    private func shouldSkipFile(_ fileURL: URL, includes: [String], excludes: [String]) -> Bool {
        let path = fileURL.path
        let fileName = fileURL.lastPathComponent

        if path.contains("/.git/") || path.contains("/.build/") || path.contains("/DerivedData/") {
            return true
        }

        if !excludes.isEmpty, matchesAnyPattern(fileName: fileName, path: path, patterns: excludes) {
            return true
        }

        if !includes.isEmpty, !matchesAnyPattern(fileName: fileName, path: path, patterns: includes) {
            return true
        }

        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              resourceValues.isRegularFile == true,
              let size = resourceValues.fileSize,
              size > 0, size <= 10 * 1024 * 1024
        else { return true }

        return false
    }

    private func processFile(
        fileURL: URL,
        query: FindInFilesQuery,
        searchEngine: SearchEngine,
        maxMatches: Int,
    ) -> [FileMatch] {
        guard let loaded = try? TextFileIO.loadTextFile(at: fileURL) else { return [] }
        let buffer = loaded.buffer
        let rawMatches = searchEngine.findAll(query: query.query, in: buffer, options: query.options)
        if rawMatches.isEmpty {
            return []
        }

        var fileMatches: [FileMatch] = []
        for match in rawMatches {
            let pos = buffer.linePosition(of: match.range.lowerBound)
            let lineRange = buffer.byteRange(ofLine: pos.line)
            let lineStart = buffer.utf16Offset(of: lineRange.lowerBound).value
            let lineEnd = buffer.utf16Offset(of: lineRange.upperBound).value
            let nsText = buffer.string as NSString

            let snippet: String = if lineEnd > lineStart, lineEnd <= nsText.length {
                nsText.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                ""
            }

            let fileMatch = FileMatch(
                line: pos.line + 1,
                column: pos.utf16Column + 1,
                range: match.range,
                lineSnippet: snippet,
            )
            fileMatches.append(fileMatch)
            if fileMatches.count >= maxMatches {
                break
            }
        }

        return fileMatches
    }

    private func parsePatterns(_ raw: String) -> [String] {
        raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func matchesAnyPattern(fileName: String, path: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if fnmatch(pattern, fileName, 0) == 0 || fnmatch(pattern, path, 0) == 0 {
                return true
            }
            if pattern.hasPrefix("*"), fileName.hasSuffix(pattern.dropFirst()) {
                return true
            }
        }
        return false
    }
}
