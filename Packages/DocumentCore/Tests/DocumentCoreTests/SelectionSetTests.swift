import DocumentCore
import Testing

struct SelectionSetTests {
    @Test func normalizedSortsAndMergesOverlappingRanges() {
        let r1 = ByteOffset(10) ..< ByteOffset(20)
        let r2 = ByteOffset(15) ..< ByteOffset(25)
        let r3 = ByteOffset(30) ..< ByteOffset(40)
        let set = SelectionSet.normalized([r3, r2, r1])

        #expect(set.ranges == [ByteOffset(10) ..< ByteOffset(25), ByteOffset(30) ..< ByteOffset(40)])
    }

    @Test func addingCaretSortsAndDeduplicates() {
        let base = SelectionSet(caretAt: ByteOffset(10))
        let next = base.addingCaret(at: ByteOffset(5))
        #expect(next.ranges == [ByteOffset(5) ..< ByteOffset(5), ByteOffset(10) ..< ByteOffset(10)])

        let dup = next.addingCaret(at: ByteOffset(5))
        #expect(dup.ranges == [ByteOffset(5) ..< ByteOffset(5), ByteOffset(10) ..< ByteOffset(10)])
    }

    @Test func togglingCaretRemovesExistingCaretOrAddsNew() {
        let set = SelectionSet(caretAt: ByteOffset(10)).addingCaret(at: ByteOffset(20))
        #expect(set.ranges.count == 2)

        let toggledOff = set.togglingCaret(at: ByteOffset(10))
        #expect(toggledOff.ranges == [ByteOffset(20) ..< ByteOffset(20)])

        let toggledOn = toggledOff.togglingCaret(at: ByteOffset(15))
        #expect(toggledOn.ranges == [ByteOffset(15) ..< ByteOffset(15), ByteOffset(20) ..< ByteOffset(20)])
    }
}
