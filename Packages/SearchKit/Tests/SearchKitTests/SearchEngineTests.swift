import DocumentCore
import SearchKit
import Testing

@Suite("SearchEngineTests")
struct SearchEngineTests {
    @Test func literalSearchCaseSensitiveAndInsensitive() {
        let engine = SearchEngine()
        let buffer = TextBuffer("Hello world\nhello MERIDIAN\nHello again")

        let caseSensitive = engine.findAll(query: "Hello", in: buffer, options: [.caseSensitive])
        #expect(caseSensitive.count == 2)
        #expect(caseSensitive[0].lineIndex == 0)
        #expect(caseSensitive[1].lineIndex == 2)

        let caseInsensitive = engine.findAll(query: "hello", in: buffer, options: [])
        #expect(caseInsensitive.count == 3)
    }

    @Test func wholeWordSearch() {
        let engine = SearchEngine()
        let buffer = TextBuffer("cat catch concatenate cat_food cat")

        let allMatches = engine.findAll(query: "cat", in: buffer, options: [])
        #expect(allMatches.count == 5)

        let wordMatches = engine.findAll(query: "cat", in: buffer, options: [.wholeWord])
        #expect(wordMatches.count == 2)
    }

    @Test func regexSearch() {
        let engine = SearchEngine()
        let buffer = TextBuffer("line 10\nline 200\nno number here")

        let matches = engine.findAll(query: #"line \d+"#, in: buffer, options: [.regularExpression])
        #expect(matches.count == 2)
        #expect(matches[0].lineIndex == 0)
        #expect(matches[1].lineIndex == 1)
    }

    @Test func findNextAndPreviousNavigation() {
        let engine = SearchEngine()
        let buffer = TextBuffer("apple banana apple cherry apple")

        let matches = engine.findAll(query: "apple", in: buffer)
        #expect(matches.count == 3)

        // Caret between match 0 and match 1
        let secondMatchOffset = matches[1].range.lowerBound
        let next = engine.findNext(query: "apple", startingAt: secondMatchOffset, in: buffer)
        #expect(next?.range == matches[1].range)

        let prev = engine.findPrevious(query: "apple", startingAt: secondMatchOffset, in: buffer)
        #expect(prev?.range == matches[0].range)

        // Wrap around test
        let pastEnd = ByteOffset(100)
        let wrappedNext = engine.findNext(query: "apple", startingAt: pastEnd, in: buffer)
        #expect(wrappedNext?.range == matches[0].range)
    }

    @Test func replaceAllTransaction() {
        let engine = SearchEngine()
        var buffer = TextBuffer("foo bar foo baz foo")

        let matches = engine.findAll(query: "foo", in: buffer)
        #expect(matches.count == 3)

        let tx = engine.buildReplaceTransaction(matches: matches, replacement: "qux", in: buffer)
        buffer.apply(tx)

        #expect(buffer.string == "qux bar qux baz qux")
    }
}
