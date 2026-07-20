import Testing
import TreeSitterJavascript

@Suite("TreeSitterJavascriptTests")
struct TreeSitterJavascriptTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_javascript() != nil)
    }
}
