import Testing
@testable import EditorUI

@Suite("MinimapViewModelTests")
struct MinimapViewModelTests {
    @Test func emptyDocumentHasNoMarks() {
        let model = MinimapViewModel(lines: [])
        #expect(model.lineCount == 0)
        #expect(model.markLengths.isEmpty)
    }

    /// The guarantee that makes the sampling below safe to introduce: for an
    /// ordinary file nothing changes, one mark per line exactly as before.
    @Test func underTheLimitKeepsOneMarkPerLine() {
        let model = MinimapViewModel(lines: ["a", "bb", "ccc"])
        #expect(model.lineCount == 3)
        #expect(model.markLengths.count == 3)
    }

    @Test func exactlyAtTheLimitStillKeepsOneMarkPerLine() {
        let lines = (0 ..< MinimapViewModel.perLineLimit).map { "line \($0)" }
        let model = MinimapViewModel(lines: lines)
        #expect(model.markLengths.count == MinimapViewModel.perLineLimit)
    }

    @Test func oneLineOverTheLimitSwitchesToSampling() {
        let lines = (0 ..< MinimapViewModel.perLineLimit + 1).map { "line \($0)" }
        let model = MinimapViewModel(lines: lines)
        #expect(model.markLengths.count == MinimapViewModel.sampleCount)
        #expect(model.lineCount == MinimapViewModel.perLineLimit + 1)
    }

    @Test func blankLinesProduceZeroLengthMarks() {
        let model = MinimapViewModel(lines: ["", "   ", "\t"])
        #expect(model.markLengths.count == 3)
        #expect(model.markLengths.allSatisfy { $0 == 0 })
    }

    @Test func markLengthGrowsWithLineLength() {
        let model = MinimapViewModel(lines: [
            String(repeating: "a", count: 5),
            String(repeating: "a", count: 100),
        ])
        #expect(model.markLengths[1] > model.markLengths[0])
    }

    /// A blank line between two long ones must not inherit their width, or
    /// the minimap stops showing the document's shape.
    @Test func blankLineBetweenLongLinesStaysEmpty() {
        let long = String(repeating: "x", count: 80)
        let model = MinimapViewModel(lines: [long, "", long])
        #expect(model.markLengths[1] == 0)
        #expect(model.markLengths[0] > 0)
        #expect(model.markLengths[2] > 0)
    }

    @Test func manyLinesDoNotGrowStorage() {
        let model = MinimapViewModel(lines: (0 ..< 200_000).map { "line \($0)" })
        #expect(model.lineCount == 200_000)
        #expect(model.markLengths.count == MinimapViewModel.sampleCount)
    }

    /// Buckets take the longest line they cover rather than an average, so a
    /// single long line in an otherwise short region stays visible.
    @Test func bucketTakesTheLongestLineItCovers() {
        var lines = (0 ..< MinimapViewModel.perLineLimit * 2).map { _ in "short" }
        lines[0] = String(repeating: "x", count: 500)
        let model = MinimapViewModel(lines: lines)
        guard let first = model.markLengths.first else {
            Issue.record("no marks produced")
            return
        }
        let shortMark = MinimapViewModel.markLength(forCharacterCount: 5)
        #expect(first > shortMark)
    }

    /// Sampling must not silently drop the tail of the document: the last
    /// bucket has to receive the last line, not fall off a rounding edge.
    @Test func samplingCoversTheLastLine() {
        var lines = (0 ..< MinimapViewModel.perLineLimit * 2).map { _ in "" }
        lines[lines.count - 1] = String(repeating: "x", count: 40)
        let model = MinimapViewModel(lines: lines)
        #expect(model.markLengths.last ?? 0 > 0)
    }

    @Test func visibleRangeIsStoredUnchanged() {
        let model = MinimapViewModel(lines: ["a"])
        model.visibleLineRange = 10 ... 40
        #expect(model.visibleLineRange == 10 ... 40)
    }

    @Test func updateReplacesPreviousContent() {
        let model = MinimapViewModel(lines: ["a", "b", "c"])
        model.update(fromLines: ["only one"])
        #expect(model.lineCount == 1)
        #expect(model.markLengths.count == 1)
    }
}
