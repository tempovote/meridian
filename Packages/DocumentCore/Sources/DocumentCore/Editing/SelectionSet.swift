/// Zero or more selection ranges (a caret is an empty range), sorted,
/// non-overlapping.
public struct SelectionSet: Hashable, Sendable {
    /// The selection ranges, in ascending order and pairwise non-overlapping.
    /// Adjacent ranges may touch (one's `upperBound` equals the next's
    /// `lowerBound`) — this includes two zero-width ranges (carets) at the
    /// same offset, since an empty range's `lowerBound` and `upperBound`
    /// are equal: `init(ranges:)` permits duplicate carets at the same
    /// position by design. Callers that need distinct caret positions
    /// (e.g. a multi-cursor editing feature) must deduplicate before
    /// constructing a `SelectionSet`.
    public var ranges: [Range<ByteOffset>]

    /// Creates a selection set from `ranges`.
    ///
    /// - Precondition: `ranges` is sorted by `lowerBound` and no two ranges
    ///   overlap (touching at a shared boundary is allowed).
    public init(ranges: [Range<ByteOffset>]) {
        for index in ranges.indices.dropFirst() {
            precondition(
                ranges[index - 1].upperBound <= ranges[index].lowerBound,
                "SelectionSet ranges must be sorted and non-overlapping",
            )
        }
        self.ranges = ranges
    }

    /// Creates a selection set holding a single caret (an empty range) at
    /// `offset`.
    public init(caretAt offset: ByteOffset) {
        ranges = [offset ..< offset]
    }

    /// The selection set with no ranges.
    public static let empty = SelectionSet(ranges: [])
}
