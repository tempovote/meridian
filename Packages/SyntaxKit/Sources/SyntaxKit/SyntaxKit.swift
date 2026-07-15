import DocumentCore

/// Placeholder module marker so the package graph builds before M4.
public enum SyntaxKitModule {
    public static let name = "SyntaxKit"
    public static let coreDependency = DocumentCoreModule.name
}
