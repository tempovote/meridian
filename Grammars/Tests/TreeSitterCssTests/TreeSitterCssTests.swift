import Testing
import TreeSitterCss

@Suite("TreeSitterCssTests")
struct TreeSitterCssTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_css() != nil)
    }
}
