import Foundation

/// Utility that lazily generates and caches synthetic corpus files in a temp
/// directory for performance budget testing.
enum PerfCorpus {
    private static let corpusDirectory: URL = {
        let tempDir = FileManager.default.temporaryDirectory
        let corpusDir = tempDir.appendingPathComponent("meridian-perf-corpus", isDirectory: true)
        try? FileManager.default.createDirectory(at: corpusDir, withIntermediateDirectories: true)
        return corpusDir
    }()

    /// 1 MB standard text file (~20,000 lines).
    static var text1MB: URL {
        getThrows {
            try ensureFile(
                named: "corpus-1mb.txt",
                targetBytes: 1_000_000,
                lineTemplate: "0123456789012345678901234567890123456789012345678\n",
            )
        }
    }

    /// 100 MB standard text file (~2,000,000 lines).
    static var text100MB: URL {
        getThrows {
            try ensureFile(
                named: "corpus-100mb.txt",
                targetBytes: 100_000_000,
                lineTemplate: "0123456789012345678901234567890123456789012345678\n",
            )
        }
    }

    /// 100 MB text file for search benchmark (~2,000 matches across 100 MB).
    static var text100MBSearch: URL {
        getThrows {
            try ensureSearchFile(
                named: "corpus-100mb-search.txt",
                targetBytes: 100_000_000,
                lineTemplate: "0123456789012345678901234567890123456789012345678\n",
                targetToken: "SEARCH_KEYWORD_TARGET_MATCH_100MB\n",
                strideLines: 1000,
            )
        }
    }

    /// 10M line log file.
    static var log10MLines: URL {
        getThrows {
            try ensureLineCountFile(
                named: "corpus-10m-lines.log",
                targetLines: 10_000_000,
                lineTemplate: "2026-07-22T00:00:00.000Z [INFO] Meridian system performance log entry\n",
            )
        }
    }

    /// Single 100 MB line (no newlines).
    static var singleLine100MB: URL {
        getThrows {
            try ensureFile(
                named: "corpus-single-line-100mb.txt",
                targetBytes: 100_000_000,
                lineTemplate: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@",
            )
        }
    }

    /// Minified JSON file (~10 MB).
    static var minifiedJSON: URL {
        getThrows {
            try ensureMinifiedJSON(named: "corpus-minified.json", targetBytes: 10_000_000)
        }
    }

    private static func getThrows(_ block: () throws -> URL) -> URL {
        do {
            return try block()
        } catch {
            fatalError("Failed to generate perf corpus: \(error)")
        }
    }

    private static func ensureFile(named name: String, targetBytes: Int, lineTemplate: String) throws -> URL {
        let fileURL = corpusDirectory.appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size >= targetBytes
        {
            return fileURL
        }

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        let patternData = Data(lineTemplate.utf8)
        let chunkSize = 1_048_576 // 1 MB buffer
        var chunk = Data()
        chunk.reserveCapacity(chunkSize)
        while chunk.count < chunkSize {
            chunk.append(patternData)
        }

        var written = 0
        while written < targetBytes {
            let toWrite = min(chunk.count, targetBytes - written)
            try handle.write(contentsOf: chunk.prefix(toWrite))
            written += toWrite
        }
        return fileURL
    }

    private static func ensureSearchFile(
        named name: String,
        targetBytes: Int,
        lineTemplate: String,
        targetToken: String,
        strideLines: Int,
    ) throws -> URL {
        let fileURL = corpusDirectory.appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size >= targetBytes
        {
            return fileURL
        }

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        let lineData = Data(lineTemplate.utf8)
        let tokenData = Data(targetToken.utf8)
        var written = 0
        var lineCount = 0

        while written < targetBytes {
            let dataToWrite = (lineCount % strideLines == 0) ? tokenData : lineData
            try handle.write(contentsOf: dataToWrite)
            written += dataToWrite.count
            lineCount += 1
        }
        return fileURL
    }

    private static func ensureLineCountFile(named name: String, targetLines: Int, lineTemplate: String) throws -> URL {
        let fileURL = corpusDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        let patternData = Data(lineTemplate.utf8)
        let linesPerChunk = 20000
        var chunk = Data()
        chunk.reserveCapacity(patternData.count * linesPerChunk)
        for _ in 0 ..< linesPerChunk {
            chunk.append(patternData)
        }

        var linesWritten = 0
        while linesWritten < targetLines {
            let batch = min(linesPerChunk, targetLines - linesWritten)
            if batch == linesPerChunk {
                try handle.write(contentsOf: chunk)
            } else {
                var smallChunk = Data()
                for _ in 0 ..< batch {
                    smallChunk.append(patternData)
                }
                try handle.write(contentsOf: smallChunk)
            }
            linesWritten += batch
        }
        return fileURL
    }

    private static func ensureMinifiedJSON(named name: String, targetBytes: Int) throws -> URL {
        let fileURL = corpusDirectory.appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size >= targetBytes
        {
            return fileURL
        }

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        let itemPattern = "{\"id\":12345,\"name\":\"item\",\"valid\":true,\"tags\":[\"a\",\"b\"]},"
        let header = "{\"status\":\"ok\",\"items\":["
        let footer = "]}"
        try handle.write(contentsOf: Data(header.utf8))
        var currentBytes = header.utf8.count + footer.utf8.count

        let itemData = Data(itemPattern.utf8)
        let chunkSize = 1_048_576
        var chunk = Data()
        while chunk.count < chunkSize {
            chunk.append(itemData)
        }

        while currentBytes < targetBytes {
            let needed = targetBytes - currentBytes
            let toWrite = min(chunk.count, needed)
            try handle.write(contentsOf: chunk.prefix(toWrite))
            currentBytes += toWrite
        }
        try handle.write(contentsOf: Data(footer.utf8))
        return fileURL
    }
}
