import EditorUI
import SettingsKit

/// Placeholder module marker so the package graph builds before M3.
public enum WorkspaceUIModule {
    public static let name = "WorkspaceUI"
    public static let editorDependency = EditorUIModule.name
}
