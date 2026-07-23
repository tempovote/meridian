import AppKit
import DocumentCore
import SettingsKit
import Testing
import ThemeKit
@testable import EditorUI

/// A fresh, unique temp directory per call — real `SettingsStore`
/// instances only (this repo doesn't mock; ARCHITECTURE §15). Mirrors the
/// helper in `FoldingEngineTests.swift`/`FoldingRenderTests.swift`.
private func testSettingsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("editorui-settings-tests-\(UUID().uuidString)")
}

/// Gutter chevron band: reserved ruler width, and click-to-fold/unfold via
/// `LineNumberRulerView.onFoldChevronClick`.
@MainActor
struct FoldingGutterTests {
    private func makeEngine() -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        return TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
    }

    @Test func rulerReservesChevronBandWhenProviderSet() {
        let engine = makeEngine()
        engine.load(buffer: TextBuffer("a\nb\n"))
        let ruler = engine.rulerViewForTesting
        let bare = ruler.ruleThickness
        // Engine wires foldMarkProvider in init, so thickness already
        // includes the band; clearing the provider shrinks it.
        ruler.foldMarkProvider = nil
        ruler.updateThickness()
        #expect(ruler.ruleThickness < bare)
    }

    @Test func chevronClickTogglesFold() async {
        let engine = makeEngine()
        engine.languageID = "swift"
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer("func f() {\n    let a = 1\n}\n"))
        await engine.waitForParseForTesting()
        engine.rulerViewForTesting.onFoldChevronClick?(0)
        #expect(engine.foldModelForTesting.folded.count == 1)
        engine.rulerViewForTesting.onFoldChevronClick?(0)
        #expect(engine.foldModelForTesting.folded.isEmpty)
    }

    /// `chevronClickTogglesFold` above exercises `onFoldChevronClick`
    /// directly, bypassing `LineNumberRulerView.mouseDown`'s own point ->
    /// fragment -> line coordinate conversion entirely. This test drives
    /// that conversion for real: a genuine `NSEvent` at a point inside the
    /// reserved chevron band, run through the actual `mouseDown` override,
    /// must resolve to line 0 — the risk this milestone's brief flagged as
    /// the most likely place for an off-by-one/coordinate-space bug. The
    /// view needs a real (offscreen) `NSWindow` for `convert(_:to:)` to
    /// perform a real view<->window transform instead of the identity
    /// no-op it falls back to for a windowless view.
    @Test func mouseDownOnChevronBandResolvesToCorrectLine() async throws {
        let engine = makeEngine()
        engine.languageID = "swift"
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer("func f() {\n    let a = 1\n}\n"))
        await engine.waitForParseForTesting()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.contentView = engine.view

        let ruler = engine.rulerViewForTesting
        var clickedLine: Int?
        ruler.onFoldChevronClick = { clickedLine = $0 }

        // Inside the reserved trailing chevron strip, on line 0's row.
        let clickPoint = NSPoint(x: ruler.ruleThickness - 4, y: 8)
        let screenPoint = ruler.convert(clickPoint, to: nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: screenPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
        ))
        ruler.mouseDown(with: event)

        #expect(clickedLine == 0)
    }

    /// Lays out fully and returns the first fragment reached from the
    /// document's start — used below to read line 0's real frame/
    /// typographic bounds for placeholder-click coordinate math. Mirrors
    /// `FoldingRenderTests`'s enumeration pattern.
    private func firstLayoutFragment(_ tlm: NSTextLayoutManager) -> NSTextLayoutFragment? {
        tlm.ensureLayout(for: tlm.documentRange)
        var first: NSTextLayoutFragment?
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            first = fragment
            return false
        }
        return first
    }

    /// Covers `handleFoldPlaceholderClick` — wired to `MeridianTextView
    /// .onFoldPlaceholderClick` by `configureFoldGutter()` — which had no
    /// automated test despite being the click-to-unfold path for the "…"
    /// badge drawn past a folded region's visible first line. Drives the
    /// callback directly with a point derived from the real layout
    /// fragment's typographic bounds: same "point -> fragment -> line"
    /// coordinate convention `mouseDownOnChevronBandResolvesToCorrectLine`
    /// exercises for the ruler, minus that test's extra ruler-space hop
    /// since this click already originates in the text view's own
    /// coordinate space.
    @Test func placeholderClickPastTypographicEndUnfoldsRegionAndBeforeItDoesNot() async throws {
        let engine = makeEngine()
        engine.languageID = "swift"
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer("func f() {\n    let a = 1\n}\n"))
        await engine.waitForParseForTesting()

        engine.rulerViewForTesting.onFoldChevronClick?(0)
        #expect(engine.foldModelForTesting.folded.count == 1)

        let tlm = try #require(engine.textView.textLayoutManager)
        let containerOriginY = engine.textView.textContainerOrigin.y

        let fragment = try #require(firstLayoutFragment(tlm))
        let lineMaxX = try #require(fragment.textLineFragments.last).typographicBounds.maxX
        let frame = fragment.layoutFragmentFrame
        let rowY = frame.origin.y + frame.height / 2 + containerOriginY

        // Past the "…" badge zone (line's typographic end): unfolds and
        // reports the click as handled.
        let pastEndPoint = NSPoint(x: frame.origin.x + lineMaxX + 5, y: rowY)
        #expect(engine.textView.onFoldPlaceholderClick?(pastEndPoint) == true)
        #expect(engine.foldModelForTesting.folded.isEmpty)
        #expect(engine.hiddenUTF16SpansForTesting.isEmpty)

        // Fold again, then click inside the visible text itself (before
        // the typographic end): must leave the fold intact and report the
        // click as unhandled, so normal caret placement proceeds instead.
        engine.rulerViewForTesting.onFoldChevronClick?(0)
        #expect(engine.foldModelForTesting.folded.count == 1)

        let refoldedFragment = try #require(firstLayoutFragment(tlm))
        let refoldedRowY = refoldedFragment.layoutFragmentFrame.origin.y
            + refoldedFragment.layoutFragmentFrame.height / 2 + containerOriginY
        let insideTextPoint = NSPoint(x: refoldedFragment.layoutFragmentFrame.origin.x + 2, y: refoldedRowY)
        #expect(engine.textView.onFoldPlaceholderClick?(insideTextPoint) == false)
        #expect(engine.foldModelForTesting.folded.count == 1)
        #expect(!engine.hiddenUTF16SpansForTesting.isEmpty)
    }
}
