import DocumentCore
import SyntaxKit
import Testing
@testable import EditorUI

@Suite("BracketMatcherTests")
struct BracketMatcherTests {
    @Test func matchesSimplePairCaretBeforeOpen() {
        let buffer = TextBuffer("foo(bar)")
        // Caret at offset 3, i.e. right before "(".
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(3), tokenRuns: nil)
        #expect(result?.open == ByteOffset(3))
        #expect(result?.close == ByteOffset(7))
    }

    @Test func matchesSimplePairCaretAfterClose() {
        let buffer = TextBuffer("foo(bar)")
        // Caret at offset 8, i.e. right after ")".
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(8), tokenRuns: nil)
        #expect(result?.open == ByteOffset(3))
        #expect(result?.close == ByteOffset(7))
    }

    @Test func matchesNestedPairsCorrectly() {
        let buffer = TextBuffer("a(b[c]d)e")
        // Caret at offset 1, right before the outer "(".
        let outer = BracketMatcher.match(in: buffer, at: ByteOffset(1), tokenRuns: nil)
        #expect(outer?.open == ByteOffset(1))
        #expect(outer?.close == ByteOffset(7))
        // Caret at offset 3, right before the inner "[".
        let inner = BracketMatcher.match(in: buffer, at: ByteOffset(3), tokenRuns: nil)
        #expect(inner?.open == ByteOffset(3))
        #expect(inner?.close == ByteOffset(5))
    }

    @Test func fallbackModeMatchesBracketInsideStringIncorrectlyOnPurpose() {
        // No tokenRuns (fallback mode): the bracket inside the string IS
        // counted, proving the fallback is a naive scan with no
        // string/comment awareness.
        let buffer = TextBuffer("\"a(b\"c)")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(2), tokenRuns: nil)
        #expect(result?.open == ByteOffset(2))
        #expect(result?.close == ByteOffset(6))
    }

    @Test func treeAwareModeSkipsBracketInsideStringRun() {
        // "a(b" is a .string run (bytes 0..4), "c)" is .plain/.punctuation
        // (bytes 4..7 conceptually) — the "(" inside the string must be
        // invisible to the scan, so there is no real ")" to match it and
        // the result must be nil, not the "c)" byte.
        let buffer = TextBuffer("\"a(b\"c)")
        let runs = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(5), type: .string),
            TokenRun(range: ByteOffset(5) ..< ByteOffset(6), type: .plain),
            TokenRun(range: ByteOffset(6) ..< ByteOffset(7), type: .punctuation),
        ]
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(2), tokenRuns: runs)
        #expect(result == nil)
    }

    @Test func treeAwareModeStillMatchesRealBracketsOutsideStrings() {
        let buffer = TextBuffer("foo(bar)")
        let runs = [
            TokenRun(range: ByteOffset(0) ..< ByteOffset(3), type: .function),
            TokenRun(range: ByteOffset(3) ..< ByteOffset(4), type: .punctuation),
            TokenRun(range: ByteOffset(4) ..< ByteOffset(7), type: .variable),
            TokenRun(range: ByteOffset(7) ..< ByteOffset(8), type: .punctuation),
        ]
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(3), tokenRuns: runs)
        #expect(result?.open == ByteOffset(3))
        #expect(result?.close == ByteOffset(7))
    }

    @Test func unmatchedBracketReturnsNil() {
        let buffer = TextBuffer("foo(bar")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(3), tokenRuns: nil)
        #expect(result == nil)
    }

    @Test func caretNotAdjacentToBracketReturnsNil() {
        let buffer = TextBuffer("foo(bar)")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(1), tokenRuns: nil)
        #expect(result == nil)
    }

    @Test func caretAtStartOfBufferDoesNotCrash() {
        let buffer = TextBuffer("(x)")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(0), tokenRuns: nil)
        #expect(result?.open == ByteOffset(0))
        #expect(result?.close == ByteOffset(2))
    }

    @Test func caretAtEndOfBufferDoesNotCrash() {
        let buffer = TextBuffer("(x)")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(3), tokenRuns: nil)
        #expect(result?.open == ByteOffset(0))
        #expect(result?.close == ByteOffset(2))
    }

    @Test func angleBracketsAreNotMatched() {
        let buffer = TextBuffer("a<b>c")
        let result = BracketMatcher.match(in: buffer, at: ByteOffset(1), tokenRuns: nil)
        #expect(result == nil)
    }
}
