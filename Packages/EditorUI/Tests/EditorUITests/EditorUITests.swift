import Testing
@testable import EditorUI

@Test func dependencyGraphWired() {
    #expect(EditorUIModule.coreDependency == "DocumentCore")
}
