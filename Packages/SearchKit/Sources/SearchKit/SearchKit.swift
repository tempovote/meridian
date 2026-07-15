import DocumentCore

/// Placeholder module marker so the package graph builds before M3.
public enum SearchKitModule {
    public static let name = "SearchKit"
    public static let coreDependency = DocumentCoreModule.name
}
