import Foundation
import Testing
@testable import SettingsKit

@Suite("SettingsDecodingTests")
struct SettingsDecodingTests {
    @Test func decodesCompleteSettingsJSON() throws {
        let json = """
        {
          "schemaVersion": 1,
          "editor": {
            "fontFamily": "Menlo",
            "fontSize": 14,
            "tabWidth": 2,
            "softWrapDefault": false
          }
        }
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.schemaVersion == 1)
        #expect(settings.editor.fontFamily == "Menlo")
        #expect(settings.editor.fontSize == 14)
        #expect(settings.editor.tabWidth == 2)
        #expect(settings.editor.softWrapDefault == false)
    }

    @Test func missingEditorObjectDefaultsEntirely() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.schemaVersion == 1)
        #expect(settings.editor == EditorSettings.default)
    }

    @Test func missingIndividualEditorFieldsDefaultIndividually() throws {
        let json = """
        { "editor": { "fontSize": 20 } }
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.editor.fontSize == 20)
        #expect(settings.editor.fontFamily == EditorSettings.default.fontFamily)
        #expect(settings.editor.tabWidth == EditorSettings.default.tabWidth)
        #expect(settings.editor.softWrapDefault == EditorSettings.default.softWrapDefault)
    }

    @Test func encodesAllFourEditorFields() throws {
        let settings = Settings(schemaVersion: 1, editor: EditorSettings(
            fontFamily: "Menlo", fontSize: 15, tabWidth: 8, softWrapDefault: true,
        ))
        let data = try JSONEncoder().encode(settings)
        let roundTripped = try JSONDecoder().decode(Settings.self, from: data)
        #expect(roundTripped == settings)
    }
}
