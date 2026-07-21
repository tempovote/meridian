import Foundation
import Testing
@testable import SettingsKit

@MainActor
@Suite("SettingsStoreTests")
struct SettingsStoreTests {
    /// A fresh, unique temp directory per test — `SettingsStore` creates
    /// it if missing, mirroring the real app-support directory.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("settingskit-tests-\(UUID().uuidString)")
        return dir
    }

    @Test func missingFileStartsAtDefaults() throws {
        let store = SettingsStore(directoryURL: try makeTempDir())
        #expect(store.current == Settings.default)
        #expect(store.lastLoadError == nil)
    }

    @Test func updateWritesFileAndUpdatesCurrent() throws {
        let dir = try makeTempDir()
        let store = SettingsStore(directoryURL: dir)
        store.update { $0.editor.fontSize = 18 }
        #expect(store.current.editor.fontSize == 18)

        let url = dir.appendingPathComponent("settings.json")
        let reloaded = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
        #expect(reloaded.editor.fontSize == 18)
    }

    @Test func loadsExistingFileAtInit() throws {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "editor": { "fontFamily": "Menlo", "fontSize": 16, "tabWidth": 2, "softWrapDefault": false } }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))

        let store = SettingsStore(directoryURL: dir)
        #expect(store.current.editor.fontFamily == "Menlo")
        #expect(store.current.editor.fontSize == 16)
    }

    @Test func malformedFileAtInitFallsBackToDefaultsWithError() throws {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("settings.json"))

        let store = SettingsStore(directoryURL: dir)
        #expect(store.current == Settings.default)
        #expect(store.lastLoadError != nil)
    }

    @Test func unknownTopLevelKeysSurviveARoundTrip() throws {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "editor": {}, "future": { "flag": true } }
        """
        let url = dir.appendingPathComponent("settings.json")
        try Data(json.utf8).write(to: url)

        let store = SettingsStore(directoryURL: dir)
        store.update { $0.editor.fontSize = 20 }

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let future = raw?["future"] as? [String: Any]
        #expect(future?["flag"] as? Bool == true)
    }

    @Test func onChangeFiresOnUpdate() throws {
        let store = SettingsStore(directoryURL: try makeTempDir())
        var observedSize: Double?
        store.onChange { settings in observedSize = settings.editor.fontSize }
        store.update { $0.editor.fontSize = 22 }
        #expect(observedSize == 22)
    }
}
