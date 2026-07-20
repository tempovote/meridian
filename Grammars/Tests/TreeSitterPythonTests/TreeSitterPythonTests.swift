import Testing
import TreeSitterPython

@Suite("TreeSitterPythonTests")
struct TreeSitterPythonTests {
    @Test func languageFunctionReturnsNonNilPointer() {
        #expect(tree_sitter_python() != nil)
    }
}
