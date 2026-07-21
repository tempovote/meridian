import Observation
import SettingsKit

/// Binds the Preferences window's four editable fields to a
/// ``SettingsStore``. Every setter writes through immediately (no
/// separate Save button — ARCHITECTURE §14's "Preferences UI is just a
/// pretty editor for settings.json"). Registers with the store's
/// `onChange` to also reflect *external* edits (hand-editing the file, or
/// a live reload) without creating a feedback loop in either direction:
/// `syncFromStore` only assigns a property when it actually differs
/// (so a UI-originated edit, where `self` already holds the new value,
/// never re-triggers its own `didSet`), AND `isSyncingFromStore` guards
/// every `didSet` (so a store-originated assignment — where the value
/// DOES differ, e.g. an external hand-edit — never writes back through
/// `store.update`, which would otherwise silently re-persist/reformat a
/// file the user just edited by hand).
@MainActor
@Observable
public final class PreferencesViewModel {
    private let store: SettingsStore
    @ObservationIgnored private var isSyncingFromStore = false

    public var fontFamily: String {
        didSet {
            guard fontFamily != oldValue, !isSyncingFromStore else { return }
            store.update { $0.editor.fontFamily = fontFamily }
        }
    }

    public var fontSize: Double {
        didSet {
            guard fontSize != oldValue, !isSyncingFromStore else { return }
            store.update { $0.editor.fontSize = fontSize }
        }
    }

    public var tabWidth: Int {
        didSet {
            guard tabWidth != oldValue, !isSyncingFromStore else { return }
            store.update { $0.editor.tabWidth = tabWidth }
        }
    }

    public var softWrapDefault: Bool {
        didSet {
            guard softWrapDefault != oldValue, !isSyncingFromStore else { return }
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
        isSyncingFromStore = true
        defer { isSyncingFromStore = false }
        let editor = settings.editor
        if fontFamily != editor.fontFamily {
            fontFamily = editor.fontFamily
        }
        if fontSize != editor.fontSize {
            fontSize = editor.fontSize
        }
        if tabWidth != editor.tabWidth {
            tabWidth = editor.tabWidth
        }
        if softWrapDefault != editor.softWrapDefault {
            softWrapDefault = editor.softWrapDefault
        }
        bannerMessage = store.lastLoadError?.errorDescription
    }
}
