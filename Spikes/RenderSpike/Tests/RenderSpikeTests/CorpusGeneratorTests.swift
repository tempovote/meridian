import Foundation
import Testing
@testable import renderspike

@Test func corpusGenerationIsDeterministicAndSized() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("renderspike-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let a = dir.appendingPathComponent("a.txt")
    let b = dir.appendingPathComponent("b.txt")
    try CorpusGenerator.generate(kind: .mixedText, sizeBytes: 2_000_000, seed: 0xC0FFEE, to: a)
    try CorpusGenerator.generate(kind: .mixedText, sizeBytes: 2_000_000, seed: 0xC0FFEE, to: b)

    let dataA = try Data(contentsOf: a)
    let dataB = try Data(contentsOf: b)
    #expect(dataA == dataB, "same seed must produce identical corpora")
    // Sized within one line-batch of the target (generator stops at/after target).
    #expect(dataA.count >= 2_000_000 && dataA.count < 2_100_000)
    // Must be valid UTF-8 with mixed content.
    let text = try #require(String(bytes: dataA, encoding: .utf8))
    #expect(text.contains("\n"))
}

@Test func logCorpusIsLineCounted() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("renderspike-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("log.txt")
    try CorpusGenerator.generate(kind: .logLines, sizeBytes: 1_000_000, seed: 1, to: url)
    let text = try #require(String(bytes: try Data(contentsOf: url), encoding: .utf8))
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count > 5_000, "log corpus should be many short lines")
}

@Test func singleLineCorpusHasNoNewlines() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("renderspike-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("single.txt")
    try CorpusGenerator.generate(kind: .singleLine, sizeBytes: 1_000_000, seed: 1, to: url)
    let data = try Data(contentsOf: url)
    #expect(!data.contains(0x0A), "single-line corpus must contain no \\n")
}
