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
        .appendingPathComponent("editorui-settings-tests-\(UUID().uuidString)")
}

/// Renders a real TextKit 2 engine offscreen and asserts hidden line spans
/// produce zero-height layout fragments (the fold primitive) while the
/// content storage keeps the full text.
@MainActor
struct FoldingRenderTests {
    private func makeEngine(_ text: String) -> TextKit2Engine {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        // Give the view a real size so TextKit 2 lays out (same trick as
        // existing TextKit2EngineTests / SoftWrapAndChromeTests).
        engine.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        engine.load(buffer: TextBuffer(text))
        return engine
    }

    @Test func hiddenSpanCollapsesFragmentsToZeroHeight() throws {
        let engine = makeEngine("line0\nline1\nline2\nline3\nline4\n")
        engine.setHiddenLineSpans([1 ... 2].map { Range($0) })

        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)

        var heightsByLine: [Int: CGFloat] = [:]
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let offset = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            let line = engine.snapshotForTesting
                .linePosition(of: engine.snapshotForTesting.byteOffset(of: UTF16Offset(offset))).line
            heightsByLine[line] = fragment.layoutFragmentFrame.height
            return true
        }
        #expect(heightsByLine[0] ?? 0 > 0)
        #expect(heightsByLine[1] == 0)
        #expect(heightsByLine[2] == 0)
        #expect(heightsByLine[3] ?? 0 > 0)
        // Content storage still holds the full text — folding is display-only.
        #expect(engine.storageStringForTesting == "line0\nline1\nline2\nline3\nline4\n")
    }

    @Test func clearingSpansRestoresHeights() throws {
        let engine = makeEngine("a\nb\nc\n")
        engine.setHiddenLineSpans([1 ... 1].map { Range($0) })
        engine.setHiddenLineSpans([])
        let tlm = try #require(engine.textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        var zeroHeightCount = 0
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            if fragment.layoutFragmentFrame.height == 0 {
                zeroHeightCount += 1
            }
            return true
        }
        #expect(zeroHeightCount == 0)
    }
}
