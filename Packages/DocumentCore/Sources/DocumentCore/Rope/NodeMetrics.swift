/// Internal O(log n) descent primitives converting between the buffer's
/// coordinate systems (UTF-8 bytes, UTF-16 units, and line numbers).
///
/// All four share the same descent shape: at an `.inner` node, walk children
/// left-to-right subtracting whole-subtree summary fields until the target
/// falls inside a child, then recurse; at a `.leaf`, scan the partial byte
/// prefix (at most `Leaf.maxBytes` bytes) to finish the count.
extension Node {
    /// UTF-16 length of the first `byteOffset` bytes. Precondition: 0...utf8, scalar boundary.
    func utf16Length(upToByte byteOffset: Int) -> Int {
        precondition(
            (0 ... summary.utf8).contains(byteOffset),
            "byteOffset \(byteOffset) out of range 0...\(summary.utf8)",
        )
        switch self {
        case let .leaf(leaf):
            precondition(
                isScalarBoundary(leaf.bytes, byteOffset),
                "byteOffset \(byteOffset) is not a scalar boundary",
            )
            let prefix = Summary(scanning: leaf.bytes[..<byteOffset])
            assert(prefix.utf8 == byteOffset, "scanned prefix length must match byteOffset")
            return prefix.utf16

        case let .inner(children, _, _):
            var remaining = byteOffset
            var index = 0
            while index < children.count - 1, remaining > children[index].summary.utf8 {
                remaining -= children[index].summary.utf8
                index += 1
            }
            return Self.childUTF16Offset(children, upTo: index) + children[index].utf16Length(upToByte: remaining)
        }
    }

    /// Byte length of the first `utf16Offset` UTF-16 units. Precondition: 0...utf16,
    /// must not land inside a surrogate pair (checked at the leaf).
    func byteLength(upToUTF16 utf16Offset: Int) -> Int {
        precondition(
            (0 ... summary.utf16).contains(utf16Offset),
            "utf16Offset \(utf16Offset) out of range 0...\(summary.utf16)",
        )
        switch self {
        case let .leaf(leaf):
            return Node.byteLength(inLeaf: leaf.bytes, upToUTF16: utf16Offset)

        case let .inner(children, _, _):
            var remaining = utf16Offset
            var index = 0
            while index < children.count - 1, remaining > children[index].summary.utf16 {
                remaining -= children[index].summary.utf16
                index += 1
            }
            return Self.childUTF8Offset(children, upTo: index) + children[index].byteLength(upToUTF16: remaining)
        }
    }

    /// Byte offset where line `line` starts (0-based; line 0 → 0; line k → after k-th LF).
    /// Precondition: 0...summary.newlines.
    func byteOffsetOfLineStart(_ line: Int) -> Int {
        precondition(
            (0 ... summary.newlines).contains(line),
            "line \(line) out of range 0...\(summary.newlines)",
        )
        guard line > 0 else { return 0 }
        return offsetAfterNewline(number: line)
    }

    /// Number of LF bytes strictly before `byteOffset`. Precondition: 0...utf8.
    func newlines(beforeByte byteOffset: Int) -> Int {
        precondition(
            (0 ... summary.utf8).contains(byteOffset),
            "byteOffset \(byteOffset) out of range 0...\(summary.utf8)",
        )
        switch self {
        case let .leaf(leaf):
            let prefix = Summary(scanning: leaf.bytes[..<byteOffset])
            assert(prefix.utf8 == byteOffset, "scanned prefix length must match byteOffset")
            return prefix.newlines

        case let .inner(children, _, _):
            var remaining = byteOffset
            var index = 0
            while index < children.count - 1, remaining > children[index].summary.utf8 {
                remaining -= children[index].summary.utf8
                index += 1
            }
            return Self.childNewlineCount(children, upTo: index) + children[index].newlines(beforeByte: remaining)
        }
    }

    // MARK: - Private helpers

    /// Sum of `utf16` summaries of `children[..<index]` — the running base
    /// offset to add to a recursive call into `children[index]`.
    private static func childUTF16Offset(_ children: [Node], upTo index: Int) -> Int {
        children[..<index].reduce(0) { $0 + $1.summary.utf16 }
    }

    /// Sum of `utf8` summaries of `children[..<index]`.
    private static func childUTF8Offset(_ children: [Node], upTo index: Int) -> Int {
        children[..<index].reduce(0) { $0 + $1.summary.utf8 }
    }

    /// Sum of `newlines` summaries of `children[..<index]`.
    private static func childNewlineCount(_ children: [Node], upTo index: Int) -> Int {
        children[..<index].reduce(0) { $0 + $1.summary.newlines }
    }

    /// Descends to the leaf containing the `number`-th newline (1-based),
    /// scans it to find the newline's local index, and returns the global
    /// byte offset just after it.
    private func offsetAfterNewline(number: Int) -> Int {
        switch self {
        case let .leaf(leaf):
            var seen = 0
            for (index, byte) in leaf.bytes.enumerated() where byte == 0x0A {
                seen += 1
                if seen == number {
                    return index + 1
                }
            }
            preconditionFailure("leaf scan did not find newline #\(number)")

        case let .inner(children, _, _):
            var remaining = number
            var baseOffset = 0
            for child in children {
                if remaining <= child.summary.newlines {
                    return baseOffset + child.offsetAfterNewline(number: remaining)
                }
                remaining -= child.summary.newlines
                baseOffset += child.summary.utf8
            }
            preconditionFailure("inner node's children do not contain newline #\(number)")
        }
    }

    /// Leaf-level scan for `byteLength(upToUTF16:)`: walks scalars
    /// accumulating UTF-16 units until `utf16Offset` is met exactly.
    /// `bytes` never splits a scalar (a `Leaf` invariant), so starting at 0
    /// and jumping by each scalar's byte length stays on scalar boundaries.
    private static func byteLength(inLeaf bytes: [UInt8], upToUTF16 utf16Offset: Int) -> Int {
        var unitsSeen = 0
        var index = 0
        while index < bytes.count {
            if unitsSeen == utf16Offset {
                return index
            }
            let lead = bytes[index]
            let width = lead >= 0xF0 ? 2 : 1 // 4-byte scalars need a surrogate pair
            precondition(
                utf16Offset != unitsSeen + 1 || width != 2,
                "utf16Offset \(utf16Offset) lands inside a surrogate pair",
            )
            var next = index + 1
            while next < bytes.count, !isScalarBoundary(bytes, next) {
                next += 1
            }
            unitsSeen += width
            index = next
        }
        assert(unitsSeen == utf16Offset, "utf16Offset \(utf16Offset) must be fully consumed by end of leaf")
        return index
    }
}
