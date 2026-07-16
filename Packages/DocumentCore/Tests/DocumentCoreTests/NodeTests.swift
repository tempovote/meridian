import Testing
@testable import DocumentCore

@Test func buildEmptyIsEmptyLeaf() {
    let node = Node.build(from: [])
    #expect(node.height == 0)
    #expect(node.summary == .zero)
    #expect(node.allBytes.isEmpty)
    #expect(node.checkInvariants().isEmpty)
}

@Test func buildSmallStaysLeaf() {
    let bytes = Array("hello".utf8)
    let node = Node.build(from: bytes)
    #expect(node.height == 0)
    #expect(node.allBytes == bytes)
}

@Test func buildLargeCreatesTree() {
    // 100k bytes → ≥ 49 leaves at 2048B → height ≥ 2 with fanout 16.
    let bytes = Array(String(repeating: "abcdefghij", count: 10000).utf8)
    let node = Node.build(from: bytes)
    #expect(node.height >= 2)
    #expect(node.allBytes == bytes)
    #expect(node.summary == Summary(scanning: bytes))
    #expect(node.checkInvariants().isEmpty)
}

@Test func buildMultibyteRoundTrips() {
    let text = String(repeating: "tiếng Việt 🇻🇳 日本語\n", count: 500)
    let bytes = Array(text.utf8)
    let node = Node.build(from: bytes)
    #expect(node.allBytes == bytes)
    #expect(node.summary == Summary(scanning: bytes))
    #expect(node.checkInvariants().isEmpty)
}

@Test func forEachLeafVisitsInOrder() {
    let bytes = Array(String(repeating: "0123456789", count: 1000).utf8)
    let node = Node.build(from: bytes)
    var collected: [UInt8] = []
    node.forEachLeaf { collected.append(contentsOf: $0.bytes) }
    #expect(collected == bytes)
}
