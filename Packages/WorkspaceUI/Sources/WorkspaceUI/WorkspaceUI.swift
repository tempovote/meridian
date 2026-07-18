import EditorUI
import SettingsKit

/// Placeholder module marker so the package graph builds before M3.
/// `EditorUI`'s own placeholder marker (`EditorUIModule`) was replaced by
/// real content in the M3 P1 editor-core work (Tasks 3-4); the dependency
/// name is now a literal rather than a cross-package symbol reference.
public enum WorkspaceUIModule {
    public static let name = "WorkspaceUI"
    public static let editorDependency = "EditorUI"
}
