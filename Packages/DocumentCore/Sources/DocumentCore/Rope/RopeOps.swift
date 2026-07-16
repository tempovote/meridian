/// Purely functional rope operations: split, concat, insert, remove.
///
/// None of these mutate `self` — every operation builds new nodes,
/// structurally sharing untouched subtrees. `concat` is the one primitive
/// the others are built from (Ropey/Xi-style): it height-balances by
/// grafting the shorter tree into an edge child of the taller tree and
/// repairing fanout on the way back up, splitting an overflowed node into
/// two and letting the parent absorb the extra.
extension Node {
    /// Concatenates `left` and `right` into one height-balanced tree.
    /// Empty sides (`summary.utf8 == 0`) are treated as the identity.
    static func concat(_ left: Node, _ right: Node) -> Node {
        if left.summary.utf8 == 0 {
            return right
        }
        if right.summary.utf8 == 0 {
            return left
        }
        let merged = concatNodes(left, right)
        return merged.count == 1 ? merged[0] : makeInner(merged)
    }

    /// Merges two nodes, returning either a single node (the common case)
    /// or two nodes of the same height (when the merge overflowed
    /// `maxFanout` and had to split). The caller wraps a two-element
    /// result in a fresh parent.
    private static func concatNodes(_ left: Node, _ right: Node) -> [Node] {
        if left.height == right.height {
            switch (left, right) {
            case let (.leaf(leftLeaf), .leaf(rightLeaf)):
                return leafNodes(fromCombining: leftLeaf.bytes, rightLeaf.bytes)
            case let (.inner(leftChildren, _, _), .inner(rightChildren, _, _)):
                // Merge at the seam (last child of left, first child of
                // right) so adjacent underfull leaves get a chance to
                // combine, then repack the resulting child list.
                let seam = concatNodes(leftChildren[leftChildren.count - 1], rightChildren[0])
                let combined = Array(leftChildren.dropLast()) + seam + Array(rightChildren.dropFirst())
                return packChildren(Array(combined))
            default:
                preconditionFailure("equal-height nodes must both be leaves or both be inner")
            }
        } else if left.height > right.height {
            guard case let .inner(children, _, _) = left else {
                preconditionFailure("a leaf always has height 0, so it cannot be taller")
            }
            let merged = concatNodes(children[children.count - 1], right)
            let combined = children.dropLast() + merged
            return packChildren(Array(combined))
        } else {
            guard case let .inner(children, _, _) = right else {
                preconditionFailure("a leaf always has height 0, so it cannot be taller")
            }
            let merged = concatNodes(left, children[0])
            let combined = merged + children.dropFirst()
            return packChildren(Array(combined))
        }
    }

    /// Combines two leaves' bytes into one node (if it fits `maxBytes`) or
    /// two nodes (splitting the combined run back into `maxBytes`-sized,
    /// scalar-safe chunks via `Leaf.leaves`).
    private static func leafNodes(fromCombining left: [UInt8], _ right: [UInt8]) -> [Node] {
        let combined = left + right
        guard !combined.isEmpty else { return [.leaf(Leaf(bytes: []))] }
        return Leaf.leaves(from: combined).map(Node.leaf)
    }

    /// Packs a child list into one inner node, or two if it overflows
    /// `maxFanout`. Every call site bounds `children.count` to at most
    /// `2 * maxFanout`, so a single midpoint split always suffices.
    private static func packChildren(_ children: [Node]) -> [Node] {
        if children.count <= maxFanout {
            return [makeInner(children)]
        }
        let mid = children.count / 2
        return [makeInner(Array(children[..<mid])), makeInner(Array(children[mid...]))]
    }

    /// Splits `self` at `byteOffset`, which must be a scalar boundary in
    /// `0...summary.utf8`. Empty sides are `.leaf(Leaf(bytes: []))`.
    func split(at byteOffset: Int) -> (Node, Node) {
        precondition((0 ... summary.utf8).contains(byteOffset), "split offset out of range")
        switch self {
        case let .leaf(leaf):
            precondition(isScalarBoundary(leaf.bytes, byteOffset), "split offset not a scalar boundary")
            let leftBytes = Array(leaf.bytes[..<byteOffset])
            let rightBytes = Array(leaf.bytes[byteOffset...])
            return (.leaf(Leaf(bytes: leftBytes)), .leaf(Leaf(bytes: rightBytes)))

        case let .inner(children, _, _):
            // Walk children accumulating byte offsets until the one
            // containing `byteOffset` is found; recurse into it and fold
            // the untouched siblings on either side with `concat`.
            var remaining = byteOffset
            var index = 0
            while index < children.count - 1, remaining > children[index].summary.utf8 {
                remaining -= children[index].summary.utf8
                index += 1
            }
            let (childLeft, childRight) = children[index].split(at: remaining)

            let leftParts = Array(children[..<index]) + [childLeft]
            let rightParts = [childRight] + Array(children[(index + 1)...])
            let leftNode = leftParts.dropFirst().reduce(leftParts[0]) { Node.concat($0, $1) }
            let rightNode = rightParts.dropFirst().reduce(rightParts[0]) { Node.concat($0, $1) }
            return (leftNode, rightNode)
        }
    }

    /// Inserts `bytes` at `byteOffset` (a scalar boundary).
    func inserting(_ bytes: [UInt8], at byteOffset: Int) -> Node {
        guard !bytes.isEmpty else { return self }
        let (left, right) = split(at: byteOffset)
        let middle = Node.build(from: bytes)
        return Node.concat(Node.concat(left, middle), right)
    }

    /// Removes `range` (scalar-boundary bounds) from `self`.
    func removing(_ range: Range<Int>) -> Node {
        guard !range.isEmpty else { return self }
        let (left, rest) = split(at: range.lowerBound)
        let (_, right) = rest.split(at: range.upperBound - range.lowerBound)
        return Node.concat(left, right)
    }
}
