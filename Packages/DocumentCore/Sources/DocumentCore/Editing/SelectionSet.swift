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

    /// Creates a selection set by sorting `inputRanges` and merging any overlapping
    /// or touching ranges.
    public static func normalized(_ inputRanges: [Range<ByteOffset>]) -> SelectionSet {
        guard !inputRanges.isEmpty else { return .empty }
        let sorted = inputRanges.sorted { r1, r2 in
            if r1.lowerBound != r2.lowerBound {
                return r1.lowerBound < r2.lowerBound
            }
            return r1.upperBound < r2.upperBound
        }

        var merged: [Range<ByteOffset>] = []
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let overlapsOrAdjacent = range.lowerBound < last.upperBound
                || (range.lowerBound == last.upperBound && (range.isEmpty || last.isEmpty))
            if overlapsOrAdjacent {
                let newStart = min(last.lowerBound, range.lowerBound)
                let newEnd = max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = newStart ..< newEnd
            } else {
                merged.append(range)
            }
        }
        return SelectionSet(ranges: merged)
    }

    /// Returns a new `SelectionSet` with a caret added at `offset`.
    public func addingCaret(at offset: ByteOffset) -> SelectionSet {
        var newRanges = ranges
        newRanges.append(offset ..< offset)
        return SelectionSet.normalized(newRanges)
    }

    /// Returns a new `SelectionSet` with the caret at `offset` toggled: removed if
    /// a caret exists at `offset`, or added if not.
    public func togglingCaret(at offset: ByteOffset) -> SelectionSet {
        if let index = ranges.firstIndex(where: { $0.isEmpty && $0.lowerBound == offset }) {
            var newRanges = ranges
            newRanges.remove(at: index)
            return SelectionSet(ranges: newRanges)
        } else {
            return addingCaret(at: offset)
        }
    }
}
