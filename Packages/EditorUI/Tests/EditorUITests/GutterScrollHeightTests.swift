import AppKit
import DocumentCore
import SettingsKit
import Testing
import ThemeKit
@testable import EditorUI

/// A fresh, unique temp directory per call — real `SettingsStore`
/// instances only (this repo doesn't mock; ARCHITECTURE §15).
private func testSettingsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("editorui-gutter-scroll-tests-\(UUID().uuidString)")
}

/// Regression cover for the gutter collapsing a large file's scrollable
/// height on first open.
///
/// `LineNumberRulerView.drawHashMarksAndLabels` used to call
/// `updateThickness()`, whose `ruleThickness` assignment re-tiles the
/// scroll view and so invalidates every TextKit 2 layout — including the
/// whole-document size estimate `NSTextView` derives its document height
/// from. That was harmless only for as long as the same draw pass then
/// enumerated the entire document with `.ensuresLayout` and rebuilt the
/// full height (the O(document) cost that made large files lag). Once that
/// enumeration was scoped to the viewport, the invalidation stayed and the
/// only layout that followed covered one screenful: the document view
/// collapsed to the visible height and the file could not be scrolled
/// until a window resize grew the viewport.
@MainActor
struct GutterScrollHeightTests {
    private func makeEngine() -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        return TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
    }

    private func buffer(lines: Int) -> TextBuffer {
        TextBuffer((0 ..< lines).map { "line \($0) some content here" }.joined(separator: "\n"))
    }

    /// Sizes `engine`'s view inside a real (offscreen) window, mirroring the
    /// app's own order: `MeridianDocument.makeWindowControllers` loads the
    /// buffer into a still-frame-zero, window-less engine and only then puts
    /// its view on screen.
    private func hostInWindow(_ engine: TextKit2Engine, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.contentView = engine.view
        engine.view.frame = NSRect(x: 0, y: 0, width: 800, height: height)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    /// Runs the real draw path (ruler labels + text view background), which
    /// is where the collapse happened. `display()` alone does not reach it
    /// for an offscreen window.
    private func forceDraw(_ window: NSWindow) {
        guard let root = window.contentView,
              let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)
        else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
    }

    @Test func documentStaysScrollableAfterFirstGutterDraw() throws {
        let engine = makeEngine()
        engine.load(buffer: buffer(lines: 3000))

        let viewportHeight: CGFloat = 600
        let window = hostInWindow(engine, height: viewportHeight)
        let layoutManager = try #require(engine.textView.textLayoutManager)

        let beforeDraw = layoutManager.usageBoundsForTextContainer.height
        #expect(beforeDraw > viewportHeight * 4, "3000 lines must size far beyond one viewport")

        forceDraw(window)

        // The whole-document height must survive the gutter's draw pass.
        #expect(layoutManager.usageBoundsForTextContainer.height > viewportHeight * 4)
    }

    /// The gutter still has to widen with the line count — that
    /// responsibility moved out of the draw path, it was not dropped.
    @Test func gutterWidthTracksLineCountOnLoad() {
        let engine = makeEngine()
        let ruler = engine.rulerViewForTesting

        engine.load(buffer: buffer(lines: 50))
        let narrow = ruler.ruleThickness

        engine.load(buffer: buffer(lines: 100_000))
        #expect(ruler.ruleThickness > narrow)
    }

    /// Same for typing: crossing a digit boundary widens the gutter, via the
    /// deferred hop that keeps the resize out of the editing transaction.
    @Test func gutterWidthTracksLineCountWhileTyping() async {
        let engine = makeEngine()
        let ruler = engine.rulerViewForTesting

        engine.load(buffer: buffer(lines: 999))
        let narrow = ruler.ruleThickness

        // 999 -> 1001 lines: 3 digits -> 4.
        engine.simulateUserTypingForTesting(replacing: NSRange(location: 0, length: 0), with: "a\nb\n")
        for _ in 0 ..< 10 where ruler.ruleThickness == narrow {
            await Task.yield()
        }

        #expect(ruler.ruleThickness > narrow)
    }
}
