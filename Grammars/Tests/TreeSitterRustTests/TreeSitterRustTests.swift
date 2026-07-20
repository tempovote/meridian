import Testing
import TreeSitterRust

@Suite("TreeSitterRustTests")
struct TreeSitterRustTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_rust() != nil)
    }
}
