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

/// Deterministic RNG so the round-trip fuzz case is reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@MainActor
@Suite("TextKit2Engine")
struct TextKit2EngineTests {
    private func makeEngine(_ text: String) -> (TextKit2Engine, TextBuffer) {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        let buffer = TextBuffer(text)
        engine.load(buffer: buffer)
        return (engine, buffer)
    }

    @Test func loadSeedsStorage() {
        let (engine, _) = makeEngine("hello\nxin chào 🎉")
        #expect(engine.storageStringForTesting == "hello\nxin chào 🎉")
    }

    @Test func movingCaretNextToBracketAppliesBracketMatchColor() {
        let (engine, buffer) = makeEngine("foo(bar)")
        engine.setSelection(SelectionSet(caretAt: ByteOffset(3)), in: buffer)
        #expect(engine.storageAttributeForTesting(.backgroundColor, at: 3) != nil)
        #expect(engine.storageAttributeForTesting(.backgroundColor, at: 7) != nil)
    }

    @Test func movingCaretAwayFromBracketClearsHighlight() {
        let (engine, buffer) = makeEngine("foo(bar)")
        engine.setSelection(SelectionSet(caretAt: ByteOffset(3)), in: buffer)
        #expect(engine.storageAttributeForTesting(.backgroundColor, at: 3) != nil)
        engine.setSelection(SelectionSet(caretAt: ByteOffset(0)), in: buffer)
        #expect(engine.storageAttributeForTesting(.backgroundColor, at: 3) == nil)
        #expect(engine.storageAttributeForTesting(.backgroundColor, at: 7) == nil)
    }

    @Test func loadDoesNotFireOnUserEdit() {
        let themeEngine = ThemeEngine(darkTheme: BundledThemes.meridianDark, lightTheme: BundledThemes.meridianLight)
        let engine = TextKit2Engine(
            themeEngine: themeEngine,
            settingsStore: SettingsStore(directoryURL: testSettingsDirectory()),
        )
        var fired = 0
        engine.onUserEdit = { _ in fired += 1 }
        engine.load(buffer: TextBuffer("seed"))
        #expect(fired == 0)
    }

    @Test func applyMirrorsSingleEdit() {
        let (engine, buffer) = makeEngine("hello world")
        var fired = 0
        engine.onUserEdit = { _ in fired += 1 }
        // "hello world" -> "hello brave world"
        let transaction = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(6) ..< ByteOffset(6), replacement: "brave ")],
        )
        engine.apply(transaction, base: buffer)
        #expect(engine.storageStringForTesting == "hello brave world")
        #expect(fired == 0) // programmatic — no echo
    }

    @Test func applyMirrorsMultiEditInOneTransaction() {
        let (engine, buffer) = makeEngine("aXbXc")
        // Replace both X's in one transaction (sorted, non-overlapping).
        let transaction = EditTransaction(
            baseVersion: buffer.version,
            edits: [
                Edit(range: ByteOffset(1) ..< ByteOffset(2), replacement: "-"),
                Edit(range: ByteOffset(3) ..< ByteOffset(4), replacement: "="),
            ],
        )
        engine.apply(transaction, base: buffer)
        #expect(engine.storageStringForTesting == "a-b=c")
    }

    @Test func applyConvertsMultiByteOffsetsCorrectly() {
        // "é" = 2 UTF-8 bytes / 1 UTF-16 unit; "🎉" = 4 UTF-8 / 2 UTF-16.
        let (engine, buffer) = makeEngine("é🎉x")
        // Replace "x" (bytes 6..<7) with "!".
        let transaction = EditTransaction(
            baseVersion: buffer.version,
            edits: [Edit(range: ByteOffset(6) ..< ByteOffset(7), replacement: "!")],
        )
        engine.apply(transaction, base: buffer)
        #expect(engine.storageStringForTesting == "é🎉!")
    }

    @Test func applyWithRestoreSelectionFalseLeavesSelectionUnchanged() {
        let (engine, buffer) = makeEngine("hello")
        engine.setSelection(SelectionSet(caretAt: ByteOffset(2)), in: buffer)
        let base = engine.snapshotForTesting
        let transaction = EditTransaction(
            baseVersion: base.version,
            edits: [Edit(range: ByteOffset(5) ..< ByteOffset(5), replacement: "!")],
            selectionAfter: SelectionSet(caretAt: ByteOffset(6)),
            origin: .replaceAll,
        )
        engine.apply(transaction, base: base, restoreSelection: false)
        #expect(engine.storageStringForTesting == "hello!")
        #expect(engine.selection(in: engine.snapshotForTesting) == SelectionSet(caretAt: ByteOffset(2)))
    }

    @Test func simulatedTypingFiresOnUserEditWithRopeCoordinates() throws {
        let (engine, _) = makeEngine("héllo") // é at UTF-16 1, bytes 1..<3
        var received: [EditTransaction] = []
        engine.onUserEdit = { received.append($0) }
        // User types "X" after the "é" (UTF-16 index 2 == byte offset 3).
        engine.simulateUserTypingForTesting(replacing: NSRange(location: 2, length: 0), with: "X")
        let transaction = try #require(received.first)
        #expect(transaction.edits.count == 1)
        #expect(transaction.edits[0].range == (ByteOffset(3) ..< ByteOffset(3)))
        #expect(transaction.edits[0].replacement.string == "X")
        #expect(transaction.coalescingKey == .typing)
        // Engine snapshot advanced with its own edit (lockstep contract).
        #expect(engine.storageStringForTesting == "héXllo")
        #expect(engine.snapshotStringForTesting == "héXllo")
    }

    @Test func simulatedDeletionFiresDeletingKey() throws {
        let (engine, _) = makeEngine("abc")
        var received: [EditTransaction] = []
        engine.onUserEdit = { received.append($0) }
        engine.simulateUserTypingForTesting(replacing: NSRange(location: 2, length: 1), with: "")
        let transaction = try #require(received.first)
        #expect(transaction.edits[0].range == (ByteOffset(2) ..< ByteOffset(3)))
        #expect(transaction.edits[0].replacement.isEmpty)
        #expect(transaction.coalescingKey == .deleting)
        #expect(engine.storageStringForTesting == "ab")
    }

    @Test func randomRoundTripKeepsRopeAndStorageInLockstep() {
        var rng = SplitMix64(seed: 0xED170)
        let (engine, initial) = makeEngine("start 🎉 çontent\nline two\n")
        var model = initial // reference: what the authoritative buffer would hold
        engine.onUserEdit = { model.apply($0) }
        let alphabet = ["a", "é", "🎉", "\n", "xin chào", ""]
        for _ in 0 ..< 200 {
            let current = engine.snapshotForTesting
            // Pick a random scalar-aligned byte range in the CURRENT content.
            var start = Int.random(in: 0 ... current.utf8Count, using: &rng)
            while !current.isScalarBoundary(ByteOffset(start)) {
                start -= 1
            }
            var end = Int.random(in: start ... current.utf8Count, using: &rng)
            while !current.isScalarBoundary(ByteOffset(end)) {
                end -= 1
            }
            if end < start {
                end = start
            }
            let byteRange = ByteOffset(start) ..< ByteOffset(end)
            let replacement = alphabet[Int.random(in: 0 ..< alphabet.count, using: &rng)]
            if Bool.random(using: &rng) {
                // Simulated user edit (view-led path), in UTF-16 coordinates.
                let loc = current.utf16Offset(of: byteRange.lowerBound).value
                let len = current.utf16Offset(of: byteRange.upperBound).value - loc
                engine.simulateUserTypingForTesting(
                    replacing: NSRange(location: loc, length: len), with: replacement,
                )
            } else {
                // Programmatic edit (rope-led path).
                let transaction = EditTransaction(
                    baseVersion: model.version,
                    edits: [Edit(range: byteRange, replacement: replacement)],
                )
                model.apply(transaction)
                engine.apply(transaction, base: current)
            }
            #expect(engine.storageStringForTesting == model.string)
            #expect(engine.snapshotStringForTesting == model.string)
            if engine.storageStringForTesting != model.string {
                break
            }
        }
    }
}
