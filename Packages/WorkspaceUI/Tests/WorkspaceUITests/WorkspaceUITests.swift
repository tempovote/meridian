import Testing
@testable import WorkspaceUI

@Test func dependencyGraphWired() {
    #expect(WorkspaceUIModule.editorDependency == "EditorUI")
}
