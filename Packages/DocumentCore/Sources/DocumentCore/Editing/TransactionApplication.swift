public extension TextBuffer {
    /// Applies every edit in `transaction` atomically and bumps `version`
    /// exactly once.
    ///
    /// Edits are applied back-to-front (highest `range.lowerBound` first):
    /// each edit's `range` is expressed in `transaction.baseVersion`'s
    /// coordinates, and mutating from the right end first means every
    /// not-yet-applied edit's bounds — all to the left of what's already
    /// been touched — stay valid without any offset bookkeeping. Each edit
    /// splits `root` at its bounds and concatenates the replacement's rope
    /// directly (sharing its chunks, no byte copy) rather than routing
    /// through `replaceSubrange`, which would bump `version` once per edit
    /// instead of once for the whole transaction.
    ///
    /// - Precondition: `version == transaction.baseVersion`; every edit's
    ///   `range` lies within `0..<utf8Count` (inclusive of `utf8Count` at
    ///   the upper bound) and both endpoints land on scalar boundaries.
    mutating func apply(_ transaction: EditTransaction) {
        precondition(
            version == transaction.baseVersion,
            "apply requires the buffer's version to match transaction.baseVersion",
        )
        for edit in transaction.edits.reversed() {
            precondition(
                edit.range.lowerBound.value >= 0 && edit.range.upperBound.value <= utf8Count,
                "apply edit range out of bounds",
            )
            precondition(
                isScalarBoundary(edit.range.lowerBound) && isScalarBoundary(edit.range.upperBound),
                "apply edit range must fall on scalar boundaries",
            )
            let (left, rest) = root.split(at: edit.range.lowerBound.value)
            let (_, right) = rest.split(at: edit.range.upperBound.value - edit.range.lowerBound.value)
            root = Node.concat(Node.concat(left, edit.replacement.root), right)
        }
        version = BufferVersion(value: version.value + 1)
    }
}

public extension EditTransaction {
    /// The transaction that undoes `self`.
    ///
    /// `base` must be the buffer `self` was computed against
    /// (`base.version == baseVersion`) — the inverse's replacements are
    /// chunk-sharing slices of `base`'s pre-edit content, so undoing never
    /// re-copies bytes that already existed.
    ///
    /// Inverse edits are expressed in *post-apply* coordinates: walking
    /// `edits` ascending, `delta` accumulates how much every preceding edit
    /// grew or shrank the buffer, so inverse edit `i`'s range starts at
    /// `edits[i].range.lowerBound + delta` and spans exactly
    /// `edits[i].replacement`'s length — the region `apply(self)` will have
    /// put there. Its replacement is `base.slicing(edits[i].range)`: the
    /// original bytes `self` is about to overwrite.
    ///
    /// Selections are swapped (undo restores the pre-edit selection).
    /// `coalescingKey` is `nil` (an undo step is never coalesced into
    /// another edit); `origin` is preserved. The inverse's `baseVersion` is
    /// `base.version + 1` — the version `apply(self)` produces.
    ///
    /// - Precondition: `base.version == baseVersion`.
    func inverted(base: TextBuffer) -> EditTransaction {
        precondition(
            base.version == baseVersion,
            "inverted(base:) requires the base buffer the transaction was computed against " +
                "(base.version \(base.version.value) != baseVersion \(baseVersion.value))",
        )
        var delta = 0
        var inverseEdits: [Edit] = []
        inverseEdits.reserveCapacity(edits.count)
        for edit in edits {
            let lower = edit.range.lowerBound.value + delta
            let replacementCount = edit.replacement.utf8Count
            let inverseRange = ByteOffset(lower) ..< ByteOffset(lower + replacementCount)
            inverseEdits.append(Edit(range: inverseRange, replacement: base.slicing(edit.range)))
            let originalCount = edit.range.upperBound.value - edit.range.lowerBound.value
            delta += replacementCount - originalCount
        }
        return EditTransaction(
            baseVersion: BufferVersion(value: base.version.value + 1),
            edits: inverseEdits,
            selectionBefore: selectionAfter,
            selectionAfter: selectionBefore,
            coalescingKey: nil,
            origin: origin,
        )
    }
}
