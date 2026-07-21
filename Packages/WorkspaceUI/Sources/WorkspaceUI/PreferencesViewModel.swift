import Observation
import SettingsKit

/// Binds the Preferences window's four editable fields to a
/// ``SettingsStore``. Every setter writes through immediately (no
/// separate Save button — ARCHITECTURE §14's "Preferences UI is just a
/// pretty editor for settings.json"). Registers with the store's
/// `onChange` to also reflect *external* edits (hand-editing the file, or
/// a live reload) without creating a feedback loop: `syncFromStore` only
/// assigns a property when it actually differs, so an edit this view
/// model itself just made never re-triggers its own `didSet`.
@MainActor
@Observable
public final class PreferencesViewModel {
    private let store: SettingsStore

    public var fontFamily: String {
        didSet {
            guard fontFamily != oldValue else { return }
            store.update { $0.editor.fontFamily = fontFamily }
        }
    }

    public var fontSize: Double {
        didSet {
            guard fontSize != oldValue else { return }
            store.update { $0.editor.fontSize = fontSize }
        }
    }

    public var tabWidth: Int {
        didSet {
            guard tabWidth != oldValue else { return }
            store.update { $0.editor.tabWidth = tabWidth }
        }
    }

    public var softWrapDefault: Bool {
        didSet {
            guard softWrapDefault != oldValue else { return }
            store.update { $0.editor.softWrapDefault = softWrapDefault }
        }
    }

    public private(set) var bannerMessage: String?

    public init(store: SettingsStore) {
        self.store = store
        let editor = store.current.editor
        fontFamily = editor.fontFamily
        fontSize = editor.fontSize
        tabWidth = editor.tabWidth
        softWrapDefault = editor.softWrapDefault
        bannerMessage = store.lastLoadError?.errorDescription
        store.onChange { [weak self] settings in
            self?.syncFromStore(settings)
        }
    }

    private func syncFromStore(_ settings: Settings) {
        let editor = settings.editor
        if fontFamily != editor.fontFamily { fontFamily = editor.fontFamily }
        if fontSize != editor.fontSize { fontSize = editor.fontSize }
        if tabWidth != editor.tabWidth { tabWidth = editor.tabWidth }
        if softWrapDefault != editor.softWrapDefault { softWrapDefault = editor.softWrapDefault }
        bannerMessage = store.lastLoadError?.errorDescription
    }
}
