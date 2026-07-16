/// One contiguous UTF-8 chunk of the buffer plus its byte range.
///
/// A chunk's `bytes` are exactly the bytes at `range` — `bytes.count ==
/// range.count` always holds.
public struct TextChunk: Sendable {
    /// The chunk's raw UTF-8 bytes.
    public let bytes: ArraySlice<UInt8>
    /// The chunk's byte range within the buffer that produced it.
    public let range: Range<ByteOffset>
}

public extension TextBuffer {
    /// Chunks overlapping `range`, in order. The first and last chunks are
    /// trimmed to `range`; every chunk in between is a whole rope leaf.
    ///
    /// O(log n) to start iterating, O(1) amortized per chunk thereafter.
    ///
    /// - Precondition: `range` lies within `0...utf8Count` (both bounds);
    ///   unlike most of this type's public API, `range`'s bounds are **not**
    ///   required to fall on Unicode scalar boundaries — this is a
    ///   byte-level API meant for consumers like tree-sitter or a
    ///   byte-oriented search that read arbitrary byte spans.
    func chunks(in range: Range<ByteOffset>) -> ChunkSequence {
        precondition(
            range.lowerBound.value >= 0 && range.upperBound.value <= utf8Count,
            "chunks(in:) range \(range.lowerBound.value)..<\(range.upperBound.value) out of bounds 0...\(utf8Count)",
        )
        return ChunkSequence(root: root, range: range)
    }

    /// All chunks of the buffer, in order — equivalent to
    /// `chunks(in: ByteOffset(0)..<ByteOffset(utf8Count))`.
    func chunks() -> ChunkSequence {
        chunks(in: ByteOffset(0) ..< ByteOffset(utf8Count))
    }

    /// The chunk containing `offset`: its bytes run from `offset` to the end
    /// of the rope leaf that contains it. Shaped to match tree-sitter's
    /// `TSInput` read callback, which repeatedly asks for "the rest of the
    /// buffer starting here" and is happy to receive it one leaf at a time.
    ///
    /// - Precondition: `offset` lies within `0...utf8Count`; as with
    ///   `chunks(in:)`, it need not fall on a scalar boundary.
    /// - Returns: `nil` if and only if `offset == utf8Count` (nothing left
    ///   to read).
    func chunk(at offset: ByteOffset) -> TextChunk? {
        precondition(
            (0 ... utf8Count).contains(offset.value),
            "chunk(at:) offset \(offset.value) out of bounds 0...\(utf8Count)",
        )
        guard offset.value < utf8Count else { return nil }
        var iterator = ChunkIterator(root: root, range: offset ..< ByteOffset(utf8Count))
        return iterator.next()
    }
}

/// A lazily-produced sequence of `TextChunk`s over a snapshot of a
/// `TextBuffer`'s tree. Value-semantic: it captures the root `Node` at the
/// moment `chunks()`/`chunks(in:)` was called, so iterating it later is
/// stable even if the originating buffer is mutated (or dropped) in the
/// meantime — see `TextBuffer.replaceSubrange`'s copy-on-write semantics.
public struct ChunkSequence: Sequence, Sendable {
    /// The captured tree snapshot, walked independently of the live buffer.
    let root: Node
    /// The byte range this sequence yields chunks for.
    let range: Range<ByteOffset>

    /// Creates a fresh iterator, re-seeking to `range.lowerBound`.
    public func makeIterator() -> ChunkIterator {
        ChunkIterator(root: root, range: range)
    }
}

/// Iterates a `ChunkSequence`'s chunks in order.
///
/// Holds a stack of `(children, childIndex)` frames describing the path
/// from just below the root down to the current leaf's parent, plus the
/// global byte offset where the current leaf begins. `next()` emits the
/// current leaf (trimmed to the sequence's range) and advances by popping
/// frames until one has an untaken sibling, then descending that sibling's
/// leftmost path — amortized O(1) per step since each node is pushed and
/// popped at most once over a full traversal.
public struct ChunkIterator: IteratorProtocol {
    /// One step of the path from the root to the current leaf: the inner
    /// node's children, and the index of the child currently being visited.
    private struct Frame {
        let children: [Node]
        var index: Int
    }

    private var stack: [Frame] = []
    /// The leaf at the bottom of `stack`'s path, or `nil` once iteration
    /// has passed `range.upperBound` (or the tree is exhausted).
    private var currentLeaf: Leaf?
    /// The global byte offset where `currentLeaf` begins.
    private var leafStart = 0
    private let range: Range<ByteOffset>

    /// Seeks to the leaf containing `range.lowerBound` in O(log n). An
    /// empty range (including the empty buffer's single empty leaf, which
    /// would otherwise surface as a spurious empty chunk) leaves the
    /// iterator immediately exhausted.
    init(root: Node, range: Range<ByteOffset>) {
        self.range = range
        guard !range.isEmpty else { return }
        var node = root
        var nodeBase = 0
        while true {
            switch node {
            case let .leaf(leaf):
                currentLeaf = leaf
                leafStart = nodeBase
                return
            case let .inner(children, _, _):
                // `>=` (not `>`, the `split(at:)` convention): an offset
                // sitting exactly on a leaf boundary must land at the START
                // of the next leaf, or the first `next()` would emit an
                // empty chunk from the end of the previous one. Safe
                // because `range` is non-empty and in bounds, so
                // `remaining` is always strictly less than this subtree's
                // total and some child strictly contains it.
                var remaining = range.lowerBound.value - nodeBase
                var index = 0
                while index < children.count - 1, remaining >= children[index].summary.utf8 {
                    remaining -= children[index].summary.utf8
                    index += 1
                }
                nodeBase += children[..<index].reduce(0) { $0 + $1.summary.utf8 }
                stack.append(Frame(children: children, index: index))
                node = children[index]
            }
        }
    }

    /// Emits the current leaf (trimmed to `range`) and advances to the next
    /// one, or returns `nil` once `range` is exhausted.
    public mutating func next() -> TextChunk? {
        guard let leaf = currentLeaf else { return nil }
        let leafEnd = leafStart + leaf.bytes.count
        guard leafStart < range.upperBound.value else {
            currentLeaf = nil
            return nil
        }
        let trimStart = max(leafStart, range.lowerBound.value)
        let trimEnd = min(leafEnd, range.upperBound.value)
        let chunk = TextChunk(
            bytes: leaf.bytes[(trimStart - leafStart) ..< (trimEnd - leafStart)],
            range: ByteOffset(trimStart) ..< ByteOffset(trimEnd),
        )
        advance(pastLeafEnd: leafEnd)
        return chunk
    }

    /// Pops frames until one has an untaken next child, then descends that
    /// child's leftmost path to the next leaf. Leaves `currentLeaf` `nil`
    /// when the whole tree is exhausted.
    private mutating func advance(pastLeafEnd leafEnd: Int) {
        while !stack.isEmpty {
            let nextIndex = stack[stack.count - 1].index + 1
            guard nextIndex < stack[stack.count - 1].children.count else {
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].index = nextIndex
            var node = stack[stack.count - 1].children[nextIndex]
            leafStart = leafEnd
            while true {
                switch node {
                case let .leaf(leaf):
                    currentLeaf = leaf
                    return
                case let .inner(children, _, _):
                    stack.append(Frame(children: children, index: 0))
                    node = children[0]
                }
            }
        }
        currentLeaf = nil
    }
}
