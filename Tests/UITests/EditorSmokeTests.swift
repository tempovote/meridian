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
        // NSOpenPanel is neither a sheet nor a dialog in the accessibility
        // tree here — it's a top-level Window with AppKit's stable internal
        // identifier "open-panel" (confirmed via the accessibility hierarchy
        // dump on a real run), not app.sheets/app.dialogs as first guessed.
        app.typeKey("o", modifierFlags: .command)
        let openPanel = app.windows["open-panel"]
        XCTAssertTrue(openPanel.waitForExistence(timeout: 10))
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(fileURL.path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        // The document window shows the fixture content. Match on title, not
        // identifier: app.windows["smoke.txt"] looks up accessibilityIdentifier
        // (unset on NSWindow), not the title text, so it never matches.
        let textView = app.windows.matching(NSPredicate(format: "title CONTAINS 'smoke.txt'")).firstMatch.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        XCTAssertEqual(textView.value as? String, "hello\n")

        // Type at the start of the document, then save in place.
        textView.click()
        app.typeKey(.upArrow, modifierFlags: .command)  // caret to document start
        app.typeText("xin chào ")

        // Cmd+Z must reach the document's NSUndoManager (TextKit2Engine
        // hands NSTextView's own -undo:/-undoManager machinery the
        // document's manager via NSTextViewDelegate.undoManager(for:); a
        // hand-built NSWindow with no delegate would otherwise leave
        // Cmd+Z resolving to nothing useful — see MeridianDocument's
        // windowWillReturnUndoManager). TextKit2Engine sets allowsUndo =
        // false so the text view never auto-registers its own edits; if
        // the document's manager weren't wired in, Cmd+Z would be a
        // silent no-op for end users.
        //
        // Typing composed diacritics (à, chào's combining accent) can
        // arrive as more than one coalesced undo group, so repeatedly
        // press Cmd+Z (bounded) until the text view is back to the
        // pre-typing content, rather than assuming a single keystroke
        // undoes the whole typed string.
        var undoPresses = 0
        while textView.value as? String != "hello\n", undoPresses < 10 {
            app.typeKey("z", modifierFlags: .command)
            undoPresses += 1
        }
        XCTAssertEqual(
            textView.value as? String, "hello\n",
            "Cmd+Z did not revert the typed text; undo is not reaching document.undoManager",
        )
        XCTAssertGreaterThan(undoPresses, 0, "expected at least one Cmd+Z to be needed")

        // Redo the same number of steps, then continue with the original
        // save flow.
        for _ in 0 ..< undoPresses {
            app.typeKey("Z", modifierFlags: [.command, .shift])
        }
        XCTAssertEqual(textView.value as? String, "xin chào hello\n")
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
