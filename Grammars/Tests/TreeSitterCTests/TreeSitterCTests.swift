import Testing
import TreeSitterC

@Suite("TreeSitterCTests")
struct TreeSitterCTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_c() != nil)
    }
}
