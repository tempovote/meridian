import Testing
import TreeSitterTypescript

@Suite("TreeSitterTypescriptTests")
struct TreeSitterTypescriptTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_typescript() != nil)
    }
}
