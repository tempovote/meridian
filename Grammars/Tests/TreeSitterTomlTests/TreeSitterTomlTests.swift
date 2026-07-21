import Testing
import TreeSitterToml

@Suite("TreeSitterTomlTests")
struct TreeSitterTomlTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_toml() != nil)
    }
}
