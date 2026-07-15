import Testing
@testable import DocumentCore

@Test func scalarBoundaryDetection() {
    let bytes = Array("a😀b".utf8) // a | F0 9F 98 80 | b
    #expect(isScalarBoundary(bytes, 0))
    #expect(isScalarBoundary(bytes, 1)) // before emoji lead byte
    #expect(!isScalarBoundary(bytes, 2)) // inside emoji
    #expect(!isScalarBoundary(bytes, 4))
    #expect(isScalarBoundary(bytes, 5)) // after emoji
    #expect(isScalarBoundary(bytes, 6)) // == count
}

@Test func boundarySnapWalksBack() {
    let bytes = Array("a😀b".utf8)
    #expect(scalarBoundary(in: bytes, notAfter: 3) == 1)
    #expect(scalarBoundary(in: bytes, notAfter: 5) == 5)
    #expect(scalarBoundary(in: bytes, notAfter: 0) == 0)
}

@Test func leafComputesSummary() {
    let leaf = Leaf(bytes: Array("hé\n".utf8))
    #expect(leaf.summary == Summary(scanning: Array("hé\n".utf8)))
}

@Test func leavesFromBytesRespectMaxSizeAndBoundaries() {
    // 1000 copies of a 4-byte emoji = 4000 bytes: must split into >1 leaf,
    // every leaf within maxBytes, no scalar straddles a leaf edge,
    // concatenation reproduces the input.
    let bytes = Array(String(repeating: "😀", count: 1000).utf8)
    let leaves = Leaf.leaves(from: bytes)
    #expect(leaves.count >= 2)
    for leaf in leaves {
        #expect(leaf.bytes.count <= Leaf.maxBytes)
        #expect(!leaf.bytes.isEmpty)
        #expect(leaf.bytes.first.map { $0 & 0xC0 != 0x80 } == true)
    }
    #expect(leaves.flatMap(\.bytes) == bytes)
}

@Test func leavesSplitWalkBackWhenScalarStraddlesIdealEnd() {
    // 1 ASCII byte then 4-byte emojis: ideal split at 2048 lands mid-scalar
    // ((2048 - 1) % 4 != 0), forcing the boundary walk-back.
    let bytes = Array(("a" + String(repeating: "😀", count: 1500)).utf8)
    let leaves = Leaf.leaves(from: bytes)
    #expect(leaves.count >= 2)
    for leaf in leaves {
        #expect(leaf.bytes.count <= Leaf.maxBytes)
        #expect(leaf.bytes.first.map { $0 & 0xC0 != 0x80 } == true)
    }
    #expect(leaves.flatMap(\.bytes) == bytes)
    // Also verify with 3-byte scalars (2048 % 3 == 2): forces walk-back too.
    let euro = Array(String(repeating: "€", count: 1000).utf8)
    let euroLeaves = Leaf.leaves(from: euro)
    #expect(euroLeaves.flatMap(\.bytes) == euro)
    for leaf in euroLeaves {
        #expect(leaf.bytes.count <= Leaf.maxBytes)
        #expect(leaf.bytes.first.map { $0 & 0xC0 != 0x80 } == true)
    }
}

@Test func leavesFromEmptyInput() {
    #expect(Leaf.leaves(from: []).isEmpty)
}
