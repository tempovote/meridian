import Testing
import TreeSitterBash

@Suite("TreeSitterBashTests")
struct TreeSitterBashTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_bash() != nil)
    }
}
