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
}
