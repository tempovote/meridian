import Testing
import TreeSitterRuby

@Suite("TreeSitterRubyTests")
struct TreeSitterRubyTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_ruby() != nil)
    }
}
