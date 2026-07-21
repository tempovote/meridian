import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("TokenTypeTests")
struct TokenTypeTests {
    @Test func exactMatchNormalizesDirectly() {
        #expect(TokenType(captureName: "keyword") == .keyword)
        #expect(TokenType(captureName: "string") == .string)
        #expect(TokenType(captureName: "comment") == .comment)
        #expect(TokenType(captureName: "tag") == .tag)
        #expect(TokenType(captureName: "attribute") == .attribute)
    }

    @Test func dottedSuffixFallsBackToKnownPrefix() {
        #expect(TokenType(captureName: "keyword.function") == .keyword)
        #expect(TokenType(captureName: "keyword.control") == .keyword)
        #expect(TokenType(captureName: "variable.builtin") == .variable)
        #expect(TokenType(captureName: "string.special.key") == .string)
        #expect(TokenType(captureName: "constant.builtin") == .constant)
    }

    @Test func unrecognizedCaptureFallsBackToPlain() {
        #expect(TokenType(captureName: "totally.unknown.thing") == .plain)
        #expect(TokenType(captureName: "") == .plain)
    }
}
