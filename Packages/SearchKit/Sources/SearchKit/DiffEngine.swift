import Foundation

/// Classification of a line change in diff output.
public enum DiffLineKind: String, Sendable, Equatable {
    case unchanged
    case added
    case deleted
    case modified
}

/// Represents one line of text on one side of a diff view.
public struct DiffLine: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let lineNumber: Int?
    public let text: String
    public let kind: DiffLineKind

    public init(id: UUID = UUID(), lineNumber: Int?, text: String, kind: DiffLineKind) {
        self.id = id
        self.lineNumber = lineNumber
        self.text = text
        self.kind = kind
    }
}

/// A paired left-and-right line entry for side-by-side alignment.
public struct DiffPair: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let left: DiffLine
    public let right: DiffLine

    public init(id: UUID = UUID(), left: DiffLine, right: DiffLine) {
        self.id = id
        self.left = left
        self.right = right
    }
}

/// The complete diff calculation result.
public struct DiffResult: Sendable, Equatable {
    public let leftName: String
    public let rightName: String
    public let pairs: [DiffPair]
    public let addedCount: Int
    public let deletedCount: Int
    public let modifiedCount: Int

    public init(
        leftName: String,
        rightName: String,
        pairs: [DiffPair],
        addedCount: Int,
        deletedCount: Int,
        modifiedCount: Int,
    ) {
        self.leftName = leftName
        self.rightName = rightName
        self.pairs = pairs
        self.addedCount = addedCount
        self.deletedCount = deletedCount
        self.modifiedCount = modifiedCount
    }
}

/// High-performance diff calculation engine.
public enum DiffEngine {
    private struct DiffAccumulator {
        var leftIdx: Int = 1
        var rightIdx: Int = 1
        var pairs: [DiffPair] = []
        var added: Int = 0
        var deleted: Int = 0
        var modified: Int = 0
    }

    public static func diff(
        leftText: String,
        rightText: String,
        leftName: String = "Original",
        rightName: String = "Modified",
    ) -> DiffResult {
        let leftLines = leftText.components(separatedBy: .newlines)
        let rightLines = rightText.components(separatedBy: .newlines)

        let tempDir = FileManager.default.temporaryDirectory
        let fileA = tempDir.appendingPathComponent("diff_a_\(UUID().uuidString).txt")
        let fileB = tempDir.appendingPathComponent("diff_b_\(UUID().uuidString).txt")

        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }

        try? leftText.write(to: fileA, atomically: true, encoding: .utf8)
        try? rightText.write(to: fileB, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "-U100000", "--no-color", "--no-index", fileA.path, fileB.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var diffOutput = ""
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            diffOutput = String(data: data, encoding: .utf8) ?? ""
        } catch {}

        if diffOutput.isEmpty {
            if leftText == rightText {
                var pairs: [DiffPair] = []
                for (idx, line) in leftLines.enumerated() {
                    let leftLine = DiffLine(lineNumber: idx + 1, text: line, kind: .unchanged)
                    let rightLine = DiffLine(lineNumber: idx + 1, text: line, kind: .unchanged)
                    pairs.append(DiffPair(left: leftLine, right: rightLine))
                }
                return DiffResult(
                    leftName: leftName,
                    rightName: rightName,
                    pairs: pairs,
                    addedCount: 0,
                    deletedCount: 0,
                    modifiedCount: 0,
                )
            }
        }

        return parseUnifiedDiff(
            diffOutput: diffOutput,
            leftLines: leftLines,
            rightLines: rightLines,
            leftName: leftName,
            rightName: rightName,
        )
    }

    private static func extractHunkLines(diffOutput: String) -> [String] {
        let lines = diffOutput.components(separatedBy: .newlines)
        var contentLines: [String] = []
        var inHunk = false

        for line in lines {
            if line.hasPrefix("@@ ") {
                inHunk = true
                continue
            }
            if inHunk, !line.hasPrefix("\\") {
                contentLines.append(line)
            }
        }
        return contentLines
    }

    private static func parseUnifiedDiff(
        diffOutput: String,
        leftLines: [String],
        rightLines: [String],
        leftName: String,
        rightName: String,
    ) -> DiffResult {
        let contentLines = extractHunkLines(diffOutput: diffOutput)
        var state = DiffAccumulator()
        var idx = 0

        while idx < contentLines.count {
            let line = contentLines[idx]

            if line.hasPrefix(" ") {
                let text = String(line.dropFirst())
                let leftLine = DiffLine(lineNumber: state.leftIdx, text: text, kind: .unchanged)
                let rightLine = DiffLine(lineNumber: state.rightIdx, text: text, kind: .unchanged)
                state.pairs.append(DiffPair(left: leftLine, right: rightLine))
                state.leftIdx += 1
                state.rightIdx += 1
                idx += 1
            } else if line.hasPrefix("-") {
                idx = processDiffBlock(contentLines: contentLines, startIndex: idx, state: &state)
            } else if line.hasPrefix("+") {
                let addText = String(line.dropFirst())
                let leftLine = DiffLine(lineNumber: nil, text: "", kind: .unchanged)
                let rightLine = DiffLine(lineNumber: state.rightIdx, text: addText, kind: .added)
                state.pairs.append(DiffPair(left: leftLine, right: rightLine))
                state.rightIdx += 1
                state.added += 1
                idx += 1
            } else {
                idx += 1
            }
        }

        return DiffResult(
            leftName: leftName,
            rightName: rightName,
            pairs: state.pairs,
            addedCount: state.added,
            deletedCount: state.deleted,
            modifiedCount: state.modified,
        )
    }

    private static func processDiffBlock(
        contentLines: [String],
        startIndex: Int,
        state: inout DiffAccumulator,
    ) -> Int {
        var idx = startIndex
        var delGroup: [String] = []
        while idx < contentLines.count, contentLines[idx].hasPrefix("-") {
            delGroup.append(String(contentLines[idx].dropFirst()))
            idx += 1
        }
        var addGroup: [String] = []
        while idx < contentLines.count, contentLines[idx].hasPrefix("+") {
            addGroup.append(String(contentLines[idx].dropFirst()))
            idx += 1
        }

        if !delGroup.isEmpty, !addGroup.isEmpty {
            processModifiedBlock(delGroup: delGroup, addGroup: addGroup, state: &state)
        } else if !delGroup.isEmpty {
            for delText in delGroup {
                let leftLine = DiffLine(lineNumber: state.leftIdx, text: delText, kind: .deleted)
                let rightLine = DiffLine(lineNumber: nil, text: "", kind: .unchanged)
                state.pairs.append(DiffPair(left: leftLine, right: rightLine))
                state.leftIdx += 1
                state.deleted += 1
            }
        }
        return idx
    }

    private static func processModifiedBlock(
        delGroup: [String],
        addGroup: [String],
        state: inout DiffAccumulator,
    ) {
        let commonCount = min(delGroup.count, addGroup.count)
        for idxOffset in 0 ..< commonCount {
            let leftLine = DiffLine(lineNumber: state.leftIdx, text: delGroup[idxOffset], kind: .modified)
            let rightLine = DiffLine(lineNumber: state.rightIdx, text: addGroup[idxOffset], kind: .modified)
            state.pairs.append(DiffPair(left: leftLine, right: rightLine))
            state.leftIdx += 1
            state.rightIdx += 1
            state.modified += 1
        }
        if delGroup.count > commonCount {
            for idxOffset in commonCount ..< delGroup.count {
                let leftLine = DiffLine(lineNumber: state.leftIdx, text: delGroup[idxOffset], kind: .deleted)
                let rightLine = DiffLine(lineNumber: nil, text: "", kind: .unchanged)
                state.pairs.append(DiffPair(left: leftLine, right: rightLine))
                state.leftIdx += 1
                state.deleted += 1
            }
        } else if addGroup.count > commonCount {
            for idxOffset in commonCount ..< addGroup.count {
                let leftLine = DiffLine(lineNumber: nil, text: "", kind: .unchanged)
                let rightLine = DiffLine(lineNumber: state.rightIdx, text: addGroup[idxOffset], kind: .added)
                state.pairs.append(DiffPair(left: leftLine, right: rightLine))
                state.rightIdx += 1
                state.added += 1
            }
        }
    }
}
