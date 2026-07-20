import Testing
import TreeSitterXml

@Suite("TreeSitterXmlTests")
struct TreeSitterXmlTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_xml() != nil)
    }
}
