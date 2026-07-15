import PluginAPI

/// Placeholder module marker so the package graph builds before M9.
/// Becomes the XPC service target in M9 (ADR 0004).
public enum PluginHostModule {
    public static let name = "PluginHost"
    public static let apiDependency = PluginAPIModule.name
}
