import Testing
@testable import DocumentCore

@Test func splitAndRejoinRoundTrips() {
    let bytes = Array(String(repeating: "abc😀\n", count: 2000).utf8)
    let node = Node.build(from: bytes)
    for offset in [0, 8, bytes.count / 2 - 1, bytes.count] {
        let boundary = scalarBoundary(in: bytes, notAfter: offset)
        let (left, right) = node.split(at: boundary)
        #expect(left.allBytes == Array(bytes[..<boundary]))
        #expect(right.allBytes == Array(bytes[boundary...]))
        let rejoined = Node.concat(left, right)
        #expect(rejoined.allBytes == bytes)
        #expect(rejoined.checkInvariants().isEmpty)
    }
}

@Test func concatUnevenHeights() {
    let big = Node.build(from: Array(String(repeating: "0123456789", count: 5000).utf8))
    let small = Node.build(from: Array("tail".utf8))
    let joined = Node.concat(big, small)
    #expect(joined.allBytes == big.allBytes + small.allBytes)
    #expect(joined.checkInvariants().isEmpty)
    let joined2 = Node.concat(small, big)
    #expect(joined2.allBytes == small.allBytes + big.allBytes)
    #expect(joined2.checkInvariants().isEmpty)
}

@Test func insertAndRemoveMatchArrayModel() {
    var model = Array("The quick brown fox".utf8)
    var node = Node.build(from: model)
    let insertion = Array("🦊 jumps ".utf8)
    let at = 10 // scalar boundary in ASCII
    node = node.inserting(insertion, at: at)
    model.insert(contentsOf: insertion, at: at)
    #expect(node.allBytes == model)
    node = node.removing(4 ..< 9) // "quick" — ASCII, safe boundaries
    model.removeSubrange(4 ..< 9)
    #expect(node.allBytes == model)
    #expect(node.checkInvariants().isEmpty)
}

/// The core property test: 2,000 random edits vs a naive byte-array model.
/// Every 100 ops, full state + summary + invariants are compared.
@Test func randomEditScriptMatchesReferenceModel() {
    var rng = SeededRandom(seed: 0x4D45_5249_4449_414E) // any fixed seed; keep stable
    var model: [UInt8] = []
    var node = Node.build(from: [])
    for op in 0 ..< 2000 {
        if model.isEmpty || UInt64.random(in: 0 ..< 100, using: &rng) < 65 {
            let snippet = Array(fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)].utf8)
            let at = randomScalarBoundary(in: model, using: &rng)
            node = node.inserting(snippet, at: at)
            model.insert(contentsOf: snippet, at: at)
        } else {
            let bound1 = randomScalarBoundary(in: model, using: &rng)
            let bound2 = randomScalarBoundary(in: model, using: &rng)
            let range = min(bound1, bound2) ..< max(bound1, bound2)
            node = node.removing(range)
            model.removeSubrange(range)
        }
        if op % 100 == 99 {
            #expect(node.allBytes == model, "diverged at op \(op)")
            #expect(node.summary == Summary(scanning: model))
            #expect(node.checkInvariants().isEmpty, "invariants broken at op \(op)")
        }
    }
    #expect(node.allBytes == model)
}

/// Recursively asserts every non-root `.inner` node has at least
/// `Node.minFanout` children. The root is exempt (a tree can legitimately
/// have fewer children at the very top, e.g. a single small leaf).
private func assertMinFanout(_ node: Node, isRoot: Bool) {
    switch node {
    case .leaf:
        return
    case let .inner(children, _, _):
        if !isRoot {
            #expect(
                children.count >= Node.minFanout,
                "non-root inner node has \(children.count) children, below minFanout \(Node.minFanout)",
            )
        }
        for child in children {
            assertMinFanout(child, isRoot: false)
        }
    }
}

/// Regression test (forwarded from Task 4's review): `Node.build` must
/// produce trees where every non-root inner node respects `minFanout`,
/// across leaf counts that exercise the "borrow" trailing-group trick.
@Test func buildRespectsMinFanout() {
    // Leaf counts chosen to straddle maxFanout (16) boundaries: a bit over
    // one fanout group (9), just past one full group (17), two groups plus
    // a remainder (33), a case with a small trailing remainder (49), and a
    // multi-level tree (161).
    for leafCount in [9, 17, 33, 49, 161] {
        let bytes = Array(String(repeating: "x", count: Leaf.maxBytes * leafCount - 1).utf8)
        let node = Node.build(from: bytes)
        assertMinFanout(node, isRoot: true)
        #expect(node.checkInvariants().isEmpty)
    }
}

@Test func splitExactlyOnInterLeafBoundary() {
    // Build a multi-leaf, multi-child tree of ASCII, then split precisely on
    // every leaf edge — the descent must take the earlier child and produce
    // exact left/right contents.
    let bytes = Array(String(repeating: "x", count: Leaf.maxBytes * 5).utf8)
    let node = Node.build(from: bytes)
    var edges: [Int] = []
    var acc = 0
    node.forEachLeaf { leaf in
        acc += leaf.bytes.count
        edges.append(acc)
    }
    for edge in edges.dropLast() {
        let (left, right) = node.split(at: edge)
        #expect(left.summary.utf8 == edge)
        #expect(right.summary.utf8 == bytes.count - edge)
        #expect(left.checkInvariants().isEmpty)
        #expect(right.checkInvariants().isEmpty)
        #expect(Node.concat(left, right).allBytes == bytes)
    }
}
