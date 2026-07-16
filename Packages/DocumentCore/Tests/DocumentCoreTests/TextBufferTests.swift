import Testing
@testable import DocumentCore

@Test func emptyBuffer() {
    let buffer = TextBuffer()
    #expect(buffer.isEmpty)
    #expect(buffer.utf8Count == 0)
    #expect(buffer.lineCount == 1)
    #expect(buffer.string == "")
}

@Test func initFromStringRoundTrips() {
    let text = "xin chào\nthế giới 🌍\r\nline3"
    let buffer = TextBuffer(text)
    #expect(buffer.string == text)
    #expect(buffer.utf8Count == text.utf8.count)
    #expect(buffer.utf16Count == text.utf16.count)
    #expect(buffer.lineCount == 3)
}

@Test func replaceSubrangeEditsAndBumpsVersion() {
    var buffer = TextBuffer("hello world")
    let v0 = buffer.version
    buffer.replaceSubrange(ByteOffset(6) ..< ByteOffset(11), with: "Meridian")
    #expect(buffer.string == "hello Meridian")
    #expect(buffer.version > v0)
}

@Test func insertionAndDeletionViaReplace() {
    var buffer = TextBuffer("ab")
    buffer.replaceSubrange(ByteOffset(1) ..< ByteOffset(1), with: "😀") // pure insert
    #expect(buffer.string == "a😀b")
    buffer.replaceSubrange(ByteOffset(1) ..< ByteOffset(5), with: "") // pure delete
    #expect(buffer.string == "ab")
}

@Test func snapshotsAreIsolated() {
    var buffer = TextBuffer("original")
    let snapshot = buffer
    let snapshotVersion = snapshot.version
    buffer.replaceSubrange(ByteOffset(0) ..< ByteOffset(8), with: "mutated!")
    #expect(snapshot.string == "original")
    #expect(snapshot.version == snapshotVersion)
    #expect(buffer.string == "mutated!")
}

@Test func snapshotOfLargeBufferIsCheap() {
    // Behavioral proxy for O(1) snapshots: a 10 MB buffer can be copied
    // 10,000 times without materializing (would be ~100 GB if copying).
    let buffer = TextBuffer(String(repeating: "0123456789", count: 1_000_000))
    var copies: [TextBuffer] = []
    copies.reserveCapacity(10000)
    for _ in 0 ..< 10000 {
        copies.append(buffer)
    }
    #expect(copies.count == 10000)
    #expect(copies[9999].utf8Count == 10_000_000)
}

@Test func sliceExtractsSubstring() {
    let buffer = TextBuffer("hello 🌍 world")
    #expect(buffer.slice(ByteOffset(0) ..< ByteOffset(5)) == "hello")
    #expect(buffer.slice(ByteOffset(6) ..< ByteOffset(10)) == "🌍")
}

@Test func scalarBoundaryQuery() {
    let buffer = TextBuffer("a😀b")
    #expect(buffer.isScalarBoundary(ByteOffset(1)))
    #expect(!buffer.isScalarBoundary(ByteOffset(2)))
    #expect(buffer.isScalarBoundary(ByteOffset(5)))
}
