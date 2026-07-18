import XCTest

/// The thin UI smoke suite (ARCHITECTURE §15): launch → open → type →
/// save → quit. Everything deeper is unit-tested in the packages.
final class EditorSmokeTests: XCTestCase {
    @MainActor
    func testOpenTypeSaveQuit() throws {
        // Fixture in a world-readable temp dir; opened via the Open panel
        // so the sandboxed app gains user-selected access.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meridian-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("smoke.txt")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launch()

        // Untitled window appears at launch.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // Open the fixture: ⌘O → ⇧⌘G → path → Return → Return.
        app.typeKey("o", modifierFlags: .command)
        let openPanel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 10))
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(fileURL.path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        // The document window shows the fixture content.
        let textView = app.windows["smoke.txt"].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        XCTAssertEqual(textView.value as? String, "hello\n")

        // Type at the start of the document, then save in place.
        textView.click()
        app.typeKey(.upArrow, modifierFlags: .command)  // caret to document start
        app.typeText("xin chào ")
        app.typeKey("s", modifierFlags: .command)

        // Poll the file on disk for the saved content.
        let expected = "xin chào hello\n"
        let deadline = Date(timeIntervalSinceNow: 10)
        var onDisk = ""
        while Date() < deadline {
            onDisk = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            if onDisk == expected { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(onDisk, expected)

        // ⌘Q terminates cleanly (no unsaved-changes dialog: just saved).
        app.typeKey("q", modifierFlags: .command)
        let gone = app.wait(for: .notRunning, timeout: 10)
        XCTAssertTrue(gone, "app did not terminate after Cmd+Q")
    }
}
