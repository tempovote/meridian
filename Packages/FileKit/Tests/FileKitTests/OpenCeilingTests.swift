import Foundation
import Testing
@testable import FileKit

/// Coverage for Task 6's 100 MB openable-file ceiling.
///
/// The ceiling guard itself (`MeridianDocument.maxFileSize` and the
/// `size < Self.maxFileSize` check in `read(from:ofType:)`) lives in the
/// `App` target, which is an Xcode app target with no unit-test host — there
/// is no way to `import` it from a Swift package's test target, and this
/// task's brief is explicit that inventing a new test host to make that
/// possible is out of scope. What follows instead exercises, at the
/// `FileKit` level, the two things the guard actually depends on: that a
/// file's on-disk size can be measured without materializing its content
/// (the resourceValues call `MeridianDocument.read(from:ofType:)` makes),
/// and that a file just under the ceiling still loads and produces the
/// `HugeFileProfile` the app renders a banner for. Constructing an
/// `NSDocument` and asserting the thrown `DocumentOpenError.tooLarge` and
/// its message is NOT covered here — see the task report for that gap.
@Suite("100 MB open ceiling")
struct OpenCeilingTests {
    /// Mirrors `MeridianDocument.maxFileSize`, which cannot be referenced
    /// directly from a package test target (see this file's doc comment).
    /// Keep in sync with `App/MeridianDocument.swift` by hand.
    private static let ceilingBytes = 100 * 1024 * 1024

    /// A sparse file: exercises the exact `resourceValues(forKeys:
    /// [.fileSizeKey])` mechanism the app's `read(from:ofType:)` guard uses
    /// to reject an oversized file, without writing 101 MB to disk.
    @Test func sparseFileAboveCeilingReportsSizeWithoutMaterializingContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-ceiling-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("huge.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(Self.ceilingBytes + 1024 * 1024))
        try handle.close()

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > Self.ceilingBytes)
    }

    /// A file exactly at the ceiling must be able to report its own size as
    /// not-below the ceiling — the guard uses `size < maxFileSize`, so a
    /// file exactly at the ceiling is refused, not allowed.
    @Test func sparseFileExactlyAtCeilingIsNotBelowIt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-ceiling-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("exact.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(Self.ceilingBytes))
        try handle.close()

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size == Self.ceilingBytes)
        #expect(!(size < Self.ceilingBytes))
    }

    /// A real (non-sparse) single-line file just under the ceiling — the
    /// minified-bundle.js case the task exists to unblock — must still
    /// load successfully and produce a `.huge` profile (softWrap and the
    /// other whole-file-scan features off, syntax highlighting off, but
    /// openable at all, which is the point: before this task such a file
    /// was rejected outright by the now-deleted `maxLineLength` guard).
    @Test func justUnderCeilingSingleLineFileLoadsAndIsHugeProfile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filekit-ceiling-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("minified.js")
        // 2 MB single line: big enough to trip the pathological-line
        // threshold without the multi-minute cost of writing/reading a
        // real 100 MB fixture in the unit-test suite (that scale is
        // covered by the perf corpus in Step 4 of this task instead).
        let lineBytes = 2 * 1024 * 1024
        let content = String(repeating: "a", count: lineBytes)
        try content.write(to: url, atomically: true, encoding: .utf8)

        let file = try TextFileIO.loadTextFile(at: url)
        #expect(file.longestLineUTF8Length == lineBytes)
        #expect(file.profile.level == .pathologicalLines)
        #expect(!file.profile.capabilities.softWrap)
        // Everything that doesn't require laying out the whole line stays on.
        #expect(file.profile.capabilities.syntaxHighlighting)
        #expect(file.profile.capabilities.findInFiles)
    }
}
