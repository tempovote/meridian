import Testing
import TreeSitterJSON

@Suite("TreeSitterJSONTests")
struct TreeSitterJSONTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_json() != nil)
    }
}
