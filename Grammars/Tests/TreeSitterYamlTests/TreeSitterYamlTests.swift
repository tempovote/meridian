import Testing
import TreeSitterYaml

@Suite("TreeSitterYamlTests")
struct TreeSitterYamlTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_yaml() != nil)
    }
}
