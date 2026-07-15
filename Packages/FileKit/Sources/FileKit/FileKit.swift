import DocumentCore

/// Placeholder module marker so the package graph builds before M3.
public enum FileKitModule {
    public static let name = "FileKit"
    public static let coreDependency = DocumentCoreModule.name
}
