import Testing
import TreeSitterMarkdown

@Suite("TreeSitterMarkdownTests")
struct TreeSitterMarkdownTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_markdown() != nil)
    }
}
