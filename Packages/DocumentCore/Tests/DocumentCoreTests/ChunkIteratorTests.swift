import Testing
@testable import DocumentCore

@Test func fullChunksReassembleBuffer() {
    var rng = SeededRandom(seed: 0x4D31_5034)
    var text = ""
    for _ in 0 ..< 500 {
        text += fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
    }
    let buffer = TextBuffer(text)
    var collected: [UInt8] = []
    var lastEnd = 0
    for chunk in buffer.chunks() {
        #expect(chunk.range.lowerBound.value == lastEnd, "chunks must be adjacent")
        #expect(!chunk.bytes.isEmpty)
        collected.append(contentsOf: chunk.bytes)
        lastEnd = chunk.range.upperBound.value
    }
    #expect(collected == Array(text.utf8))
    #expect(lastEnd == buffer.utf8Count)
}

@Test func rangeChunksAreTrimmed() {
    let text = String(repeating: "0123456789", count: 1000) // 10k bytes, multi-leaf
    let buffer = TextBuffer(text)
    let range = ByteOffset(5) ..< ByteOffset(9995)
    var collected: [UInt8] = []
    for chunk in buffer.chunks(in: range) {
        #expect(chunk.range.lowerBound >= range.lowerBound)
        #expect(chunk.range.upperBound <= range.upperBound)
        collected.append(contentsOf: chunk.bytes)
    }
    #expect(collected == Array(Array(text.utf8)[5 ..< 9995]))
}

@Test func emptyRangeYieldsNothing() {
    let buffer = TextBuffer("hello")
    var count = 0
    for _ in buffer.chunks(in: ByteOffset(2) ..< ByteOffset(2)) {
        count += 1
    }
    #expect(count == 0)
    for _ in TextBuffer().chunks() {
        count += 1
    }
    #expect(count == 0)
}

@Test func chunkAtOffsetReturnsLeafSuffix() {
    let text = String(repeating: "abcdefgh", count: 2000) // 16k, multi-leaf
    let buffer = TextBuffer(text)
    let bytes = Array(text.utf8)
    var offset = 0
    var stitched: [UInt8] = []
    while let chunk = buffer.chunk(at: ByteOffset(offset)) {
        #expect(chunk.range.lowerBound.value == offset)
        #expect(!chunk.bytes.isEmpty)
        stitched.append(contentsOf: chunk.bytes)
        offset = chunk.range.upperBound.value
    }
    #expect(stitched == bytes)
    #expect(buffer.chunk(at: ByteOffset(buffer.utf8Count)) == nil)
    // Mid-leaf offset returns the remainder of that leaf:
    let mid = buffer.chunk(at: ByteOffset(1))
    #expect(mid?.range.lowerBound == ByteOffset(1))
}

@Test func iterationStableUnderSnapshotMutation() {
    let text = String(repeating: "0123456789", count: 1000)
    var buffer = TextBuffer(text)
    let sequence = buffer.chunks()
    buffer.replaceSubrange(ByteOffset(0) ..< ByteOffset(buffer.utf8Count), with: "gone")
    var collected: [UInt8] = []
    for chunk in sequence {
        collected.append(contentsOf: chunk.bytes)
    }
    #expect(collected == Array(text.utf8), "sequence iterates the snapshot it captured")
}

@Test func chunkAtOffsetNotOnScalarBoundaryIsAllowed() {
    // Byte-level API: tree-sitter may re-read from any byte.
    let buffer = TextBuffer("a😀b")
    let chunk = buffer.chunk(at: ByteOffset(2)) // inside 😀
    #expect(chunk?.range.lowerBound == ByteOffset(2))
    #expect(chunk.map { Array($0.bytes) } == [0x9F, 0x98, 0x80, 0x62])
}
