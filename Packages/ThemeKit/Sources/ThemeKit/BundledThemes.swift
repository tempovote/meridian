/// The 4 themes bundled with Meridian, decoded once on first access.
/// "Meridian Dark"/"Meridian Light" are the "Auto" light/dark-follow pair
/// (ARCHITECTURE §13); the two "Contrast" variants ship but have no
/// picker UI to reach them yet (M4 Phase 3 design decision 1 — deferred).
public enum BundledThemes {
    public static let meridianDark = requireLoad("meridian-dark")
    public static let meridianLight = requireLoad("meridian-light")
    public static let meridianDarkContrast = requireLoad("meridian-dark-contrast")
    public static let meridianLightContrast = requireLoad("meridian-light-contrast")

    private static func requireLoad(_ name: String) -> Theme {
        do {
            return try ThemeLoader.loadTheme(named: name)
        } catch {
            preconditionFailure("bundled theme failed to load: \(name).meridiantheme: \(error)")
        }
    }
}
