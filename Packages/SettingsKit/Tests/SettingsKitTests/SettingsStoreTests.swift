import Foundation
import Testing
@testable import SettingsKit

@MainActor
@Suite("SettingsStoreTests")
struct SettingsStoreTests {
    /// A fresh, unique temp directory per test — `SettingsStore` creates
    /// it if missing, mirroring the real app-support directory.
    private func makeTempDir() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("settingskit-tests-\(UUID().uuidString)")
    }

    @Test func missingFileStartsAtDefaults() throws {
        let store = try SettingsStore(directoryURL: makeTempDir())
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
        let store = try SettingsStore(directoryURL: makeTempDir())
        var observedSize: Double?
        store.onChange { settings in observedSize = settings.editor.fontSize }
        store.update { $0.editor.fontSize = 22 }
        #expect(observedSize == 22)
    }

    @Test func externalValidEditIsPickedUpLive() async throws {
        let dir = try makeTempDir()
        let store = SettingsStore(directoryURL: dir)
        store.update { $0.editor.fontSize = 20 } // ensures the file + directory exist

        let url = dir.appendingPathComponent("settings.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var editor = json["editor"] as? [String: Any] ?? [:]
        editor["fontSize"] = 30
        json["editor"] = editor
        try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)

        let deadline = Date().addingTimeInterval(2)
        while store.current.editor.fontSize != 30, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(store.current.editor.fontSize == 30)
        #expect(store.lastLoadError == nil)
    }

    @Test func externalMalformedEditSetsErrorWithoutClobberingCurrent() async throws {
        let dir = try makeTempDir()
        let store = SettingsStore(directoryURL: dir)
        store.update { $0.editor.fontSize = 20 }

        let url = dir.appendingPathComponent("settings.json")
        try Data("{ not valid json".utf8).write(to: url, options: .atomic)

        let deadline = Date().addingTimeInterval(2)
        while store.lastLoadError == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(store.lastLoadError != nil)
        #expect(store.current.editor.fontSize == 20) // untouched by the bad reload
    }

    /// Regression test: a subscriber (e.g. Preferences' error banner)
    /// registered *before* an external edit breaks the file must still
    /// be notified when that reload fails — not just when it succeeds.
    /// Reproduces a real bug found via manual feel-check: an
    /// already-open Preferences window's banner never appeared because
    /// `reloadFromDisk()` only called `notifyObservers()` on its success
    /// path.
    @Test func onChangeFiresEvenWhenExternalReloadFails() async throws {
        let dir = try makeTempDir()
        let store = SettingsStore(directoryURL: dir)
        store.update { $0.editor.fontSize = 20 } // ensures the file + directory exist

        var notificationCount = 0
        store.onChange { _ in notificationCount += 1 }

        let url = dir.appendingPathComponent("settings.json")
        try Data("{ not valid json".utf8).write(to: url, options: .atomic)

        let deadline = Date().addingTimeInterval(2)
        while notificationCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(notificationCount > 0)
        #expect(store.lastLoadError != nil)
    }
}
