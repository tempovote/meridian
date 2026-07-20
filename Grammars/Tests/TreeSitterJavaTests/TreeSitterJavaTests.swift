import Testing
import TreeSitterJava

@Suite("TreeSitterJavaTests")
struct TreeSitterJavaTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_java() != nil)
    }
}
