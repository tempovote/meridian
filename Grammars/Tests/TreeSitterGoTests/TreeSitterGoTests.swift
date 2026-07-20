import Testing
import TreeSitterGo

@Suite("TreeSitterGoTests")
struct TreeSitterGoTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_go() != nil)
    }
}
