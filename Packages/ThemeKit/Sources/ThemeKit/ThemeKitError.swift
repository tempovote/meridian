/// Typed errors for ThemeKit. Both cases are only reachable for a broken
/// build (a missing or malformed bundled `.meridiantheme` resource) — no
/// user-supplied theme loading exists yet (M4 Phase 3 scope), so these are
/// programmer errors, typed for testability rather than expected at runtime.
public enum ThemeKitError: Error {
    case themeResourceNotFound(name: String)
    case themeDecodingFailed(name: String, underlying: Error)
}
