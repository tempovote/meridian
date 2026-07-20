import Testing
import TreeSitterPhp

@Suite("TreeSitterPhpTests")
struct TreeSitterPhpTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_php() != nil)
    }
}
