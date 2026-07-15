import AppKit
import DocumentCore
import SyntaxKit
import ThemeKit

/// Placeholder module marker so the package graph builds before M3.
/// The TextKit 2 editor view lands here after the M2 spike (ADR 0003).
public enum EditorUIModule {
    public static let name = "EditorUI"
    public static let coreDependency = DocumentCoreModule.name
}
