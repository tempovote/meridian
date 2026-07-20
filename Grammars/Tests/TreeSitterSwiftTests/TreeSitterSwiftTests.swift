import Testing
import TreeSitterSwift

@Suite("TreeSitterSwiftTests")
struct TreeSitterSwiftTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_swift() != nil)
    }
}
