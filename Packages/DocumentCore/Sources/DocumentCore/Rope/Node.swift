/// A rope tree node: either a leaf chunk or an inner node fanning out to
/// child nodes. Immutable — edits build new nodes structurally sharing
/// unchanged subtrees (Task 5's concern).
enum Node {
    case leaf(Leaf)
    case inner([Node], Summary, height: Int)

    static let maxFanout = 16
    static let minFanout = 8

    var summary: Summary {
        switch self {
        case let .leaf(leaf): leaf.summary
        case let .inner(_, summary, _): summary
        }
    }

    var height: Int {
        switch self {
        case .leaf: 0
        case let .inner(_, _, height): height
        }
    }

    static func makeInner(_ children: [Node]) -> Node {
        precondition(!children.isEmpty && children.count <= maxFanout)
        let summary = children.reduce(Summary.zero) { $0 + $1.summary }
        return .inner(children, summary, height: children[0].height + 1)
    }

    /// Builds a balanced tree bottom-up: leaves → groups of ≤ maxFanout.
    ///
    /// A naive chunking pass can leave a trailing group under `minFanout`
    /// (e.g. 17 leaves at fanout 16 → groups of 16 and 1). When that
    /// happens and there's a previous group to borrow from, the last two
    /// groups are pooled and re-split down the middle so both land in
    /// `minFanout...maxFanout` (standard B-tree bulk-load "borrow" trick).
    /// The pooled size is always `maxFanout + r` for `1 <= r < minFanout`
    /// (only the very last group can be undersized; every group before it
    /// is exactly `maxFanout`), so an even split always lands both halves
    /// in bounds. The root — the single node left when a level collapses
    /// to one group — is exempt from `minFanout` entirely.
    static func build(from bytes: [UInt8]) -> Node {
        let leaves = Leaf.leaves(from: bytes)
        guard !leaves.isEmpty else { return .leaf(Leaf(bytes: [])) }
        var level: [Node] = leaves.map(Node.leaf)
        while level.count > 1 {
            var groups: [[Node]] = []
            var index = 0
            while index < level.count {
                let end = min(index + maxFanout, level.count)
                groups.append(Array(level[index ..< end]))
                index = end
            }
            if groups.count >= 2, groups[groups.count - 1].count < minFanout {
                let last = groups.removeLast()
                let prev = groups.removeLast()
                let combined = prev + last
                let mid = combined.count / 2
                groups.append(Array(combined[..<mid]))
                groups.append(Array(combined[mid...]))
            }
            level = groups.map(makeInner)
        }
        return level[0]
    }

    func forEachLeaf(_ body: (Leaf) -> Void) {
        switch self {
        case let .leaf(leaf): body(leaf)
        case let .inner(children, _, _): children.forEach { $0.forEachLeaf(body) }
        }
    }

    var allBytes: [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(summary.utf8)
        forEachLeaf { out.append(contentsOf: $0.bytes) }
        return out
    }

    /// Recursively verifies the structural invariants; returns one
    /// human-readable description per violation (empty = healthy).
    func checkInvariants() -> [String] {
        switch self {
        case let .leaf(leaf):
            var violations: [String] = []
            if leaf.bytes.count > Leaf.maxBytes {
                violations.append(
                    "leaf has \(leaf.bytes.count) bytes, exceeds maxBytes \(Leaf.maxBytes)",
                )
            }
            if let first = leaf.bytes.first, first & 0xC0 == 0x80 {
                violations.append("leaf starts with a UTF-8 continuation byte")
            }
            return violations

        case let .inner(children, storedSummary, storedHeight):
            var violations: [String] = []

            if !(1 ... Node.maxFanout).contains(children.count) {
                violations.append(
                    "inner node has \(children.count) children, outside 1...\(Node.maxFanout)",
                )
            }

            let childSummarySum = children.reduce(Summary.zero) { $0 + $1.summary }
            if childSummarySum != storedSummary {
                violations.append(
                    "inner node summary \(storedSummary) does not equal sum of children summaries \(childSummarySum)",
                )
            }

            if let firstChild = children.first {
                let expectedHeight = firstChild.height + 1
                if storedHeight != expectedHeight {
                    violations.append(
                        "inner node height \(storedHeight) does not equal children[0].height + 1 (\(expectedHeight))",
                    )
                }
                for child in children where child.height != firstChild.height {
                    violations.append(
                        "inner node children have mismatched heights: \(firstChild.height) vs \(child.height)",
                    )
                }
            }

            for child in children {
                violations.append(contentsOf: child.checkInvariants())
            }
            return violations
        }
    }
}
