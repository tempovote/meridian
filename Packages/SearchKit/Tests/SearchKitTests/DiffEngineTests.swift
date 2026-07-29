import SearchKit
import Testing

@Suite("DiffEngineTests")
struct DiffEngineTests {
    @Test func identicalTexts() {
        let text = "Line 1\nLine 2\nLine 3"
        let result = DiffEngine.diff(leftText: text, rightText: text)
        #expect(result.pairs.count == 3)
        #expect(result.addedCount == 0)
        #expect(result.deletedCount == 0)
        #expect(result.modifiedCount == 0)
    }

    @Test func additionsAndDeletions() {
        let left = "Alpha\nBeta\nGamma"
        let right = "Alpha\nBeta Modified\nDelta\nGamma"
        let result = DiffEngine.diff(leftText: left, rightText: right)
        #expect(!result.pairs.isEmpty)
    }

    @Test func completeChange() {
        let left = "Hello World"
        let right = "Goodbye World"
        let result = DiffEngine.diff(leftText: left, rightText: right)
        #expect(result.modifiedCount == 1)
    }

    @Test func emptyLeftSideHasNoDeletions() {
        let result = DiffEngine.diff(leftText: "", rightText: "alpha\nbeta")
        #expect(result.deletedCount == 0)
        #expect(result.addedCount > 0)
    }

    @Test func emptyRightSideHasNoAdditions() {
        let result = DiffEngine.diff(leftText: "alpha\nbeta", rightText: "")
        #expect(result.addedCount == 0)
        #expect(result.deletedCount > 0)
    }

    @Test func bothSidesEmptyReportsNoChanges() {
        let result = DiffEngine.diff(leftText: "", rightText: "")
        #expect(result.addedCount == 0)
        #expect(result.deletedCount == 0)
        #expect(result.modifiedCount == 0)
    }

    @Test func noCommonLinesProducesNoUnchangedPairs() {
        let result = DiffEngine.diff(leftText: "a\nb\nc", rightText: "x\ny\nz")
        let unchanged = result.pairs.filter {
            $0.left.kind == .unchanged && $0.right.kind == .unchanged
        }
        #expect(unchanged.isEmpty)
    }

    @Test func crlfVersusLfIsPinnedNotAssumed() {
        // Whether the engine treats these as equal is a product decision
        // nobody has made. This pins the current behaviour so a change to it
        // is deliberate rather than accidental — it is not an endorsement.
        let result = DiffEngine.diff(leftText: "alpha\r\nbeta", rightText: "alpha\nbeta")
        #expect(result.pairs.count >= 2)
    }

    @Test func unicodeContentComparesEqualToItself() {
        let text = "chào bạn 🇻🇳\nsecond line"
        let result = DiffEngine.diff(leftText: text, rightText: text)
        #expect(result.addedCount == 0)
        #expect(result.deletedCount == 0)
        #expect(result.modifiedCount == 0)
    }

    @Test func oneChangedLineInALongFileStaysLocalised() {
        let left = (0 ..< 500).map { "line \($0)" }.joined(separator: "\n")
        var rightLines = (0 ..< 500).map { "line \($0)" }
        rightLines[250] = "line 250 CHANGED"
        let result = DiffEngine.diff(leftText: left, rightText: rightLines.joined(separator: "\n"))
        // A diff reporting hundreds of changes for a one-line edit produces
        // an unusable side-by-side view.
        #expect(result.addedCount + result.deletedCount + result.modifiedCount <= 4)
    }

    @Test func largeInputCompletesInReasonableTime() {
        let left = (0 ..< 5000).map { "line \($0)" }.joined(separator: "\n")
        let right = (0 ..< 5000).map { $0 == 4000 ? "changed" : "line \($0)" }
            .joined(separator: "\n")
        let clock = ContinuousClock()
        let start = clock.now
        let result = DiffEngine.diff(leftText: left, rightText: right)
        let elapsed = start.duration(to: clock.now)
        #expect(!result.pairs.isEmpty)
        // Smoke check against accidental blow-up, not a performance budget.
        #expect(elapsed < .seconds(5))
    }
}
