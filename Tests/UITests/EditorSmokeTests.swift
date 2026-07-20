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

        // Confirming Open can race the Go-to-Folder sheet's dismissal animation
        // on slower CI hardware: a Return sent while that sheet is still closing
        // is swallowed instead of reaching the panel's default Open button,
        // leaving open-panel open indefinitely. Root-caused via CI diagnostic
        // capture (see #15): "open-panel still open: true" after exactly one
        // confirm Return. Retry, bounded, until the panel actually closes
        // rather than trusting a single keystroke to land.
        var openConfirmPresses = 0
        while openPanel.exists, openConfirmPresses < 10 {
            app.typeKey(.return, modifierFlags: [])
            openConfirmPresses += 1
            _ = waitForDisappearance(of: openPanel, timeout: 1)
        }
        XCTAssertFalse(openPanel.exists, "open-panel did not close after \(openConfirmPresses) confirm Return presses")

        // The document window shows the fixture content. Match on title, not
        // identifier: app.windows["smoke.txt"] looks up accessibilityIdentifier
        // (unset on NSWindow), not the title text, so it never matches.
        //
        // Timeout is generous (not the suite's usual 10s): confirmed via CI log
        // timing comparison (see issue #15) that creating a *new* document window
        // via the Open panel is the one AX-heavy path in this suite slow enough
        // to occasionally exceed 10s on GitHub Actions' macOS runners, while an
        // identical local run resolves it in ~1s.
        let textView = app.windows.matching(NSPredicate(format: "title CONTAINS 'smoke.txt'")).firstMatch.textViews
            .firstMatch
        XCTAssertTrue(
            textView.waitForExistence(timeout: 25),
            // Diagnostic only (evaluated lazily, zero cost on pass): disambiguates
            // "open-panel never actually closed" (second Return raced its dismissal)
            // from "panel closed but no correctly-titled document window appeared".
            "open-panel still open: \(openPanel.exists); "
                + "window titles: \(app.windows.allElementsBoundByIndex.map(\.title)); "
                + "sheet count: \(app.sheets.count)",
        )
        XCTAssertEqual(textView.value as? String, "hello\n")

        // Type at the start of the document, then save in place.
        textView.click()
        app.typeKey(.upArrow, modifierFlags: .command) // caret to document start
        app.typeText("xin chào ")

        // Cmd+Z must reach the document's NSUndoManager (TextKit2Engine
        // hands NSTextView's own -undo:/-undoManager machinery the
        // document's manager via NSTextViewDelegate.undoManager(for:) —
        // see MeridianDocument.makeWindowControllers, which wires
        // engine.documentUndoManager = undoManager). TextKit2Engine sets
        // allowsUndo = false so the text view never auto-registers its own
        // edits; if the document's manager weren't wired in, Cmd+Z would be
        // a silent no-op for end users.
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
            if onDisk == expected {
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(onDisk, expected)

        // ⌘Q terminates cleanly (no unsaved-changes dialog: just saved).
        app.typeKey("q", modifierFlags: .command)
        let gone = app.wait(for: .notRunning, timeout: 10)
        XCTAssertTrue(gone, "app did not terminate after Cmd+Q")
    }

    /// Regression guard for the window-delegate removal: with no explicit
    /// `NSWindowDelegate` on `MeridianDocument`, `NSWindowController`'s
    /// default `windowShouldClose:` must still route Cmd+W on a dirty
    /// document through the standard "unsaved changes" review sheet,
    /// rather than closing silently. Only asserts the sheet appears, then
    /// backs out via Cancel — never exercises Save/Don't Save, so no file
    /// or app state is left behind.
    @MainActor
    func testDirtyDocumentCmdWPromptsToSave() {
        let app = XCUIApplication()
        app.launch()

        // Untitled window appears at launch, already a dirty-able target.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))

        textView.click()
        app.typeText("unsaved change")

        app.typeKey("w", modifierFlags: .command)

        let unsavedSheet = app.sheets.firstMatch
        XCTAssertTrue(
            unsavedSheet.waitForExistence(timeout: 10),
            "Cmd+W on a dirty document did not present an unsaved-changes review sheet",
        )

        // Back out without saving or discarding.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForDisappearance(of: unsavedSheet, timeout: 10),
            "unsaved-changes sheet did not dismiss after Escape",
        )

        app.terminate()
    }

    /// UI smoke test for Phase 2 chrome menu bar shortcuts (Line Numbers, Soft Wrap).
    @MainActor
    func testChromeToggles() {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Exercise View menu shortcuts (Cmd+Alt+L for line numbers, Cmd+Alt+W for soft wrap)
        app.typeKey("l", modifierFlags: [.command, .option])
        app.typeKey("w", modifierFlags: [.command, .option])

        app.terminate()
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
