import Testing
@testable import WorkspaceUI

@Suite("ANSIParserTests")
struct ANSIParserTests {
    @Test func plainTextIsOneDefaultSegment() {
        let segments = ANSIParser.parse("hello world")
        #expect(segments == [ANSISegment(text: "hello world", color: .default)])
    }

    @Test func emptyInputProducesNoSegments() {
        #expect(ANSIParser.parse("").isEmpty)
    }

    @Test func singleColourSequenceColoursTheFollowingText() {
        let segments = ANSIParser.parse("\u{1B}[31mred text")
        #expect(segments == [ANSISegment(text: "red text", color: .standard(31))])
    }

    @Test func resetReturnsToDefault() {
        let segments = ANSIParser.parse("\u{1B}[31mred\u{1B}[0mplain")
        #expect(segments == [
            ANSISegment(text: "red", color: .standard(31)),
            ANSISegment(text: "plain", color: .default),
        ])
    }

    @Test func textBeforeTheFirstSequenceKeepsDefaultColour() {
        let segments = ANSIParser.parse("plain\u{1B}[32mgreen")
        #expect(segments == [
            ANSISegment(text: "plain", color: .default),
            ANSISegment(text: "green", color: .standard(32)),
        ])
    }

    @Test func brightColoursAreDistinguishedFromStandard() {
        let segments = ANSIParser.parse("\u{1B}[91mbright red")
        #expect(segments == [ANSISegment(text: "bright red", color: .bright(91))])
    }

    @Test func compoundSequenceUsesTheColourCode() {
        // "bold red": the parser tracks colour only, so 1 is ignored and 31 wins.
        let segments = ANSIParser.parse("\u{1B}[1;31mbold red")
        #expect(segments == [ANSISegment(text: "bold red", color: .standard(31))])
    }

    @Test func unterminatedSequenceDoesNotSwallowTheRest() {
        // No closing 'm'. The remaining text must still surface rather than
        // vanishing — a terminal that eats output on malformed input is worse
        // than one that shows it uncoloured.
        let segments = ANSIParser.parse("before\u{1B}[31")
        let combined = segments.map(\.text).joined()
        #expect(combined.contains("before"))
        #expect(!segments.isEmpty)
    }

    @Test func unsupportedCodeLeavesColourUnchanged() {
        let segments = ANSIParser.parse("\u{1B}[31ma\u{1B}[7mb")
        #expect(segments == [
            ANSISegment(text: "a", color: .standard(31)),
            ANSISegment(text: "b", color: .standard(31)),
        ])
    }

    @Test func escapeWithoutBracketIsTreatedAsText() {
        let segments = ANSIParser.parse("a\u{1B}b")
        #expect(segments.map(\.text).joined().contains("b"))
    }

    @Test func consecutiveSequencesProduceNoEmptySegments() {
        let segments = ANSIParser.parse("\u{1B}[31m\u{1B}[32mgreen")
        #expect(segments == [ANSISegment(text: "green", color: .standard(32))])
    }

    @Test func allStandardAndBrightCodesAreRecognised() {
        for code in 30 ... 37 {
            let segments = ANSIParser.parse("\u{1B}[\(code)mx")
            #expect(segments == [ANSISegment(text: "x", color: .standard(code))])
        }
        for code in 90 ... 97 {
            let segments = ANSIParser.parse("\u{1B}[\(code)mx")
            #expect(segments == [ANSISegment(text: "x", color: .bright(code))])
        }
    }

    /// A trailing sequence with no text after it must not produce a segment
    /// carrying an empty string — the view renders one `Text` per segment, so
    /// an empty one is an invisible row that still costs layout.
    @Test func trailingSequenceProducesNoEmptySegment() {
        let segments = ANSIParser.parse("done\u{1B}[0m")
        #expect(segments == [ANSISegment(text: "done", color: .default)])
    }

    /// The last colour code in one sequence wins. `parseANSI` returned on the
    /// first recognised code instead; this pins the corrected order so the
    /// difference is deliberate rather than discovered later.
    @Test func lastColourCodeInASequenceWins() {
        let segments = ANSIParser.parse("\u{1B}[31;32mgreen")
        #expect(segments == [ANSISegment(text: "green", color: .standard(32))])
    }
}
