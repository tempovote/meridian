/// A monotonically increasing stamp identifying a point in a `TextBuffer`'s
/// edit history. Two buffers with equal versions are not guaranteed to hold
/// equal content (versions are per-instance lineages, not content hashes);
/// consumers use `BufferVersion` to detect staleness of cached results
/// derived from a specific snapshot.
public struct BufferVersion: Hashable, Comparable, Sendable {
    /// The raw counter value. Starts at zero for a freshly created buffer
    /// and increments by one per mutation on that buffer instance.
    public let value: UInt64

    /// Orders versions by their raw counter.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

/// The core text storage type: a persistent, copy-on-write rope of UTF-8
/// bytes.
///
/// `TextBuffer` is a value type — assigning or passing it copies a
/// lightweight handle to an immutable tree (`Node`), so making a snapshot is
/// O(1) and mutating one copy never affects another. Every mutation goes
/// through `replaceSubrange`, which rebuilds only the path from the root to
/// the edited leaves, sharing every untouched subtree with the previous
/// version.
///
/// All ranges and offsets in the public API are `ByteOffset` — UTF-8 byte
/// positions that must fall on Unicode scalar boundaries. Use
/// `isScalarBoundary(_:)` to validate an offset derived from outside the
/// buffer (e.g. from a UTF-16 or line/column conversion) before using it
/// here.
public struct TextBuffer: Sendable {
    /// Internal (not `private`) so same-module extensions — e.g.
    /// `TextBufferConversions.swift` — can descend the tree directly via the
    /// `Node` primitives instead of duplicating access through public API.
    var root: Node

    /// The version stamp of the buffer's current content. Bumped by every
    /// call to `replaceSubrange`; unaffected by copying.
    public private(set) var version: BufferVersion

    /// Creates an empty buffer at version 0.
    public init() {
        root = .leaf(Leaf(bytes: []))
        version = BufferVersion(value: 0)
    }

    /// Creates a buffer containing `string`'s UTF-8 bytes, at version 0.
    public init(_ string: some StringProtocol) {
        root = Node.build(from: Array(string.utf8))
        version = BufferVersion(value: 0)
    }

    /// The number of UTF-8 bytes in the buffer.
    public var utf8Count: Int {
        root.summary.utf8
    }

    /// The number of UTF-16 code units the buffer's content would occupy
    /// (e.g. for `NSRange`/TextKit interop).
    public var utf16Count: Int {
        root.summary.utf16
    }

    /// The number of lines in the buffer, counting `\n` as the line
    /// terminator: one more than the number of newline bytes, so an empty
    /// buffer and a buffer with no newlines both report 1.
    public var lineCount: Int {
        root.summary.newlines + 1
    }

    /// Whether the buffer holds no bytes.
    public var isEmpty: Bool {
        utf8Count == 0
    }

    /// The buffer's full content, materialized as a `String`. O(n) in the
    /// buffer's byte length — prefer `slice(_:)` for partial reads.
    public var string: String {
        // False positive: this decodes `[UInt8]`, not `Data` — the rule
        // matches on `String(decoding:as:)` syntax alone. The suggested
        // `String(bytes:encoding:)` is worse here (failable, and needs
        // Foundation, which DocumentCore otherwise avoids entirely).
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: root.allBytes, as: UTF8.self)
    }

    /// Materializes the UTF-8 bytes in `range` as a `String`.
    ///
    /// - Precondition: `range` lies within `0..<utf8Count` (inclusive of
    ///   `utf8Count` at the upper bound) and both endpoints land on scalar
    ///   boundaries.
    public func slice(_ range: Range<ByteOffset>) -> String {
        precondition(
            range.lowerBound.value >= 0 && range.upperBound.value <= utf8Count,
            "slice range out of bounds",
        )
        precondition(
            isScalarBoundary(range.lowerBound) && isScalarBoundary(range.upperBound),
            "slice range must fall on scalar boundaries",
        )
        let (_, rest) = root.split(at: range.lowerBound.value)
        let (middle, _) = rest.split(at: range.upperBound.value - range.lowerBound.value)
        // Same false positive as `string` above: decoding `[UInt8]`, not `Data`.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: middle.allBytes, as: UTF8.self)
    }

    /// Replaces the UTF-8 bytes in `range` with `newText`'s UTF-8 bytes,
    /// then bumps `version`.
    ///
    /// An empty `range` is a pure insertion; empty `newText` is a pure
    /// deletion. Structurally shares every subtree of the previous version
    /// that `range` doesn't touch.
    ///
    /// - Precondition: `range` lies within `0..<utf8Count` (inclusive of
    ///   `utf8Count` at the upper bound) and both endpoints land on scalar
    ///   boundaries.
    public mutating func replaceSubrange(_ range: Range<ByteOffset>, with newText: some StringProtocol) {
        precondition(
            range.lowerBound.value >= 0 && range.upperBound.value <= utf8Count,
            "replaceSubrange range out of bounds",
        )
        precondition(
            isScalarBoundary(range.lowerBound) && isScalarBoundary(range.upperBound),
            "replaceSubrange range must fall on scalar boundaries",
        )
        var newRoot = root
        if !range.isEmpty {
            newRoot = newRoot.removing(range.lowerBound.value ..< range.upperBound.value)
        }
        let newBytes = Array(newText.utf8)
        if !newBytes.isEmpty {
            newRoot = newRoot.inserting(newBytes, at: range.lowerBound.value)
        }
        root = newRoot
        version = BufferVersion(value: version.value + 1)
    }

    /// Whether `offset` falls on a Unicode scalar boundary (the start of
    /// the buffer, the end of the buffer, or a scalar-leading UTF-8 byte —
    /// never inside a multi-byte scalar's continuation bytes).
    ///
    /// Total over all inputs: offsets outside `0...utf8Count` return
    /// `false` rather than trapping, so callers can validate untrusted
    /// offsets with this method alone.
    ///
    /// Descends directly to the leaf containing `offset` and tests locally,
    /// in O(log n): it never materializes the buffer's full byte content.
    public func isScalarBoundary(_ offset: ByteOffset) -> Bool {
        guard (0 ... utf8Count).contains(offset.value) else { return false }
        return Self.isScalarBoundary(in: root, localOffset: offset.value)
    }

    private static func isScalarBoundary(in node: Node, localOffset: Int) -> Bool {
        switch node {
        case let .leaf(leaf):
            DocumentCore.isScalarBoundary(leaf.bytes, localOffset)
        case let .inner(children, _, _):
            isScalarBoundary(inChildren: children, localOffset: localOffset)
        }
    }

    private static func isScalarBoundary(inChildren children: [Node], localOffset: Int) -> Bool {
        var remaining = localOffset
        for child in children {
            let childLength = child.summary.utf8
            if remaining <= childLength {
                return isScalarBoundary(in: child, localOffset: remaining)
            }
            remaining -= childLength
        }
        preconditionFailure("offset out of range")
    }
}
