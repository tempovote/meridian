/// All user-facing editor preferences persisted in
/// `~/Library/Application Support/Meridian/settings.json`
/// (ARCHITECTURE §14). Missing keys default per-field (backward compat);
/// unknown top-level JSON keys are preserved separately by
/// ``SettingsStore`` on save (forward compat) — this type only models the
/// keys P1 knows about.
public struct EditorSettings: Codable, Sendable, Equatable {
    public var fontFamily: String
    public var fontSize: Double
    public var tabWidth: Int
    public var softWrapDefault: Bool

    public static let `default` = EditorSettings(
        fontFamily: "SF Mono", fontSize: 13, tabWidth: 4, softWrapDefault: true,
    )

    public init(fontFamily: String, fontSize: Double, tabWidth: Int, softWrapDefault: Bool) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.tabWidth = tabWidth
        self.softWrapDefault = softWrapDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
            ?? Self.default.fontFamily
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
            ?? Self.default.fontSize
        tabWidth = try container.decodeIfPresent(Int.self, forKey: .tabWidth)
            ?? Self.default.tabWidth
        softWrapDefault = try container.decodeIfPresent(Bool.self, forKey: .softWrapDefault)
            ?? Self.default.softWrapDefault
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, tabWidth, softWrapDefault
    }
}

/// The root settings document. `schemaVersion` exists from day one even
/// though there is no migration logic yet, so a real migration function
/// has somewhere to hook in later without a schema break.
public struct Settings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var editor: EditorSettings

    public static let `default` = Settings(schemaVersion: 1, editor: .default)

    public init(schemaVersion: Int = 1, editor: EditorSettings = .default) {
        self.schemaVersion = schemaVersion
        self.editor = editor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.default.schemaVersion
        editor = try container.decodeIfPresent(EditorSettings.self, forKey: .editor)
            ?? Self.default.editor
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, editor
    }
}
