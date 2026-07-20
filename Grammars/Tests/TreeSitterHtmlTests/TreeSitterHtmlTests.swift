import Testing
import TreeSitterHtml

@Suite("TreeSitterHtmlTests")
struct TreeSitterHtmlTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_html() != nil)
    }
}
