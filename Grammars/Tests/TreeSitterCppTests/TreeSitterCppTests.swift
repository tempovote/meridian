import Testing
import TreeSitterCpp

@Suite("TreeSitterCppTests")
struct TreeSitterCppTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_cpp() != nil)
    }
}
