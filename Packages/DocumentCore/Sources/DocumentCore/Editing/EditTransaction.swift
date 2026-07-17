/// Groups edits for undo coalescing: consecutive transactions that share a
/// `CoalescingKey` (and are otherwise adjacent/compatible) may be merged
/// into a single undo step instead of one per keystroke.
public enum CoalescingKey: Hashable, Sendable {
    /// Consecutive character insertions (e.g. regular typing).
    case typing
    /// Consecutive deletions (e.g. holding delete/backspace).
    case deleting
}

/// Where an `EditTransaction` came from, for provenance/attribution
/// (undo grouping, plugin bookkeeping, change notifications).
public enum EditOrigin: Hashable, Sendable {
    /// A direct user action (typing, pasting, etc.).
    case user
    /// An edit made by a plugin, identified by its plugin id.
    case plugin(id: String)
    /// The document was reloaded from disk.
    case reload
    /// A find-and-replace-all operation.
    case replaceAll
}

/// One replacement in base-buffer coordinates. `replacement` is a
/// rope-backed buffer — slicing an existing buffer shares chunks (no copy).
///
/// `Edit` is `Equatable`, but `TextBuffer` deliberately is not: comparing
/// two buffers' content is O(n) in their byte length, and giving
/// `TextBuffer` its own `==` would invite that cost to be paid accidentally
/// (e.g. in a collection lookup or a diffing pass) where a version or
/// identity check was meant instead. `Edit.==` opts into the O(n) cost
/// explicitly, via the private `TextBuffer.contentEquals(_:)` helper, because
/// comparing two edits for equality is inherently a content comparison.
public struct Edit: Equatable, Sendable {
    /// The base-buffer byte range this edit replaces.
    public let range: Range<ByteOffset>
    /// The text that replaces `range`'s bytes.
    public let replacement: TextBuffer

    /// Creates an edit replacing `range` with `replacement`'s content.
    public init(range: Range<ByteOffset>, replacement: TextBuffer) {
        self.range = range
        self.replacement = replacement
    }

    /// Creates an edit replacing `range` with `replacement`'s UTF-8 bytes.
    public init(range: Range<ByteOffset>, replacement: some StringProtocol) {
        self.range = range
        self.replacement = TextBuffer(replacement)
    }

    /// Compares two edits by `range` and by `replacement`'s content — an
    /// O(n) comparison in the replacement's byte length (see the type's
    /// DocC for why `Edit` opts into this cost while `TextBuffer` itself
    /// does not).
    public static func == (lhs: Edit, rhs: Edit) -> Bool {
        lhs.range == rhs.range && lhs.replacement.contentEquals(rhs.replacement)
    }
}

private extension TextBuffer {
    /// Byte-for-byte content equality. Not exposed as `Equatable`
    /// conformance on `TextBuffer` itself (see `Edit`'s DocC for why) — this
    /// is O(n) in the buffers' byte length, with a summary comparison as a
    /// fast-path rejection before falling back to a full byte compare.
    func contentEquals(_ other: TextBuffer) -> Bool {
        guard root.summary == other.root.summary else { return false }
        return root.allBytes == other.root.allBytes
    }
}

/// A single atomic unit of change to a `TextBuffer`: zero or more sorted,
/// non-overlapping `Edit`s applied against a known `baseVersion`, plus the
/// selection state before/after and metadata for undo grouping and
/// provenance.
///
/// This is the single choke point for mutating a document: undo grouping,
/// plugin hooks, and change notifications all key off `EditTransaction`
/// rather than raw buffer writes.
public struct EditTransaction: Sendable {
    /// The buffer version this transaction's edit offsets are expressed
    /// against. Consumers reject a transaction whose `baseVersion` no
    /// longer matches the current buffer.
    public let baseVersion: BufferVersion
    /// The edits to apply, sorted by range and non-overlapping (touching —
    /// one edit's `upperBound` equal to the next's `lowerBound` — is legal).
    public let edits: [Edit]
    /// The selection immediately before this transaction is applied.
    public let selectionBefore: SelectionSet
    /// The selection immediately after this transaction is applied.
    public let selectionAfter: SelectionSet
    /// If set, allows this transaction to coalesce with an adjacent one
    /// sharing the same key into a single undo step.
    public let coalescingKey: CoalescingKey?
    /// Where this transaction came from.
    public let origin: EditOrigin

    /// Creates a transaction.
    ///
    /// - Precondition: `edits` is sorted by `range.lowerBound` and no two
    ///   edits' ranges overlap (touching — one edit's `upperBound` equal to
    ///   the next's `lowerBound` — is allowed).
    public init(
        baseVersion: BufferVersion,
        edits: [Edit],
        selectionBefore: SelectionSet = .empty,
        selectionAfter: SelectionSet = .empty,
        coalescingKey: CoalescingKey? = nil,
        origin: EditOrigin = .user,
    ) {
        for index in edits.indices.dropFirst() {
            precondition(
                edits[index - 1].range.upperBound <= edits[index].range.lowerBound,
                "EditTransaction edits must be sorted and non-overlapping",
            )
        }
        self.baseVersion = baseVersion
        self.edits = edits
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.coalescingKey = coalescingKey
        self.origin = origin
    }
}
