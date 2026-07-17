import AppKit
import DocumentCore
import Foundation
import Testing
@testable import renderspike

/// Ground truth: every paragraph the content manager vends must byte-equal
/// the corresponding line slice of the buffer (plus its trailing newline,
/// except the last line). A wrong content manager silently invalidates
/// every benchmark number — this is the one test the spike must have.
@MainActor
@Test func vendedParagraphsMatchBufferLines() throws {
    var text = ""
    var rng = SplitMix64(seed: 42)
    for i in 0 ..< 2_000 {
        switch rng.next() % 5 {
        case 0: text += "\n"
        case 1: text += "line \(i) with tiếng Việt\n"
        case 2: text += "emoji 👨‍👩‍👧‍👦 line \(i)\n"
        default: text += "plain ascii line number \(i)\n"
        }
    }
    text += "final line without trailing newline"
    let buffer = TextBuffer(text)
    let manager = RopeContentManager(buffer: buffer)

    var vendedLines = 0
    var location: NSTextLocation = manager.documentRange.location
    manager.enumerateTextElements(from: location, options: []) { element in
        guard let paragraph = element as? NSTextParagraph else {
            Issue.record("vended element is not NSTextParagraph")
            return false
        }
        guard let range = element.elementRange,
              let start = range.location as? RopeLocation,
              let end = range.endLocation as? RopeLocation else {
            Issue.record("element range missing or endpoints are not RopeLocation")
            return false
        }
        let expected = buffer.slice(start.byte ..< end.byte)
        #expect(
            paragraph.attributedString.string == expected,
            "paragraph \(vendedLines) content mismatch",
        )
        vendedLines += 1
        location = range.endLocation
        return true
    }
    #expect(vendedLines == buffer.lineCount, "must vend exactly lineCount paragraphs")
}

/// Location arithmetic round-trips: offsetBy N then offset(from:to:)
/// must return N, in UTF-16 units (TextKit's unit for element content).
///
/// DEVIATION: the brief's snippet called this `offsetedBy:`; the real
/// NSTextElementProvider selector (`locationFromLocation:withOffset:`)
/// imports into Swift as `location(_:offsetBy:)`. See RopeContentManager.swift.
@MainActor
@Test func locationArithmeticRoundTrips() throws {
    let buffer = TextBuffer("abc😀\ndef\nghi")
    let manager = RopeContentManager(buffer: buffer)
    let start = manager.documentRange.location
    for step in [0, 1, 3, 5, 7] {
        let moved = try #require(manager.location(start, offsetBy: step))
        #expect(manager.offset(from: start, to: moved) == step)
    }
}

/// Regression: forward enumeration starting at `documentRange.endLocation`
/// on a non-empty buffer must vend nothing. Before the fix, the clamp in
/// `enumerateTextElements` re-derived the last line from the clamped
/// (last valid) byte and re-vended it instead of recognizing "start is at
/// or past the end" as exhausted.
@MainActor
@Test func forwardEnumerationFromEndVendsNothing() throws {
    let buffer = TextBuffer("line one\nline two\nline three")
    let manager = RopeContentManager(buffer: buffer)
    var vended = 0
    _ = manager.enumerateTextElements(from: manager.documentRange.endLocation, options: []) { _ in
        vended += 1
        return true
    }
    #expect(vended == 0, "enumerating from documentRange.endLocation must vend nothing")
}

/// Regression: an empty buffer (`TextBuffer("")`, `lineCount == 1`) must
/// still vend exactly one paragraph, per the class's "one paragraph per
/// line" contract — a bare `guard buffer.utf8Count > 0` used to short-circuit
/// and vend zero paragraphs instead.
@MainActor
@Test func emptyBufferVendsOneEmptyParagraph() throws {
    let buffer = TextBuffer("")
    let manager = RopeContentManager(buffer: buffer)
    var vended: [String] = []
    _ = manager.enumerateTextElements(from: manager.documentRange.location, options: []) { element in
        guard let paragraph = element as? NSTextParagraph else {
            Issue.record("vended element is not NSTextParagraph")
            return false
        }
        vended.append(paragraph.attributedString.string)
        return true
    }
    #expect(vended == [""], "empty buffer must vend exactly one paragraph whose string is empty")
}

/// After scripted edits through applyEdit, vended paragraphs must still
/// match the mutated buffer exactly (reference model: apply the same edits
/// to a plain String).
@MainActor
@Test func vendingStaysCorrectAfterEdits() throws {
    var reference = "alpha\nbeta\ngamma\ndelta\nepsilon\n"
    let manager = RopeContentManager(buffer: TextBuffer(reference))

    // (byte range in CURRENT content, replacement) — applied sequentially.
    let edits: [(Range<Int>, String)] = [
        (6 ..< 10, "BETA"),          // replace "beta"
        (0 ..< 0, "zero\n"),         // insert new first line
        (5 ..< 11, ""),              // delete "alpha\n"
        (5 ..< 5, "x😀y"),           // insert emoji mid-content
    ]
    for (range, replacement) in edits {
        manager.applyEdit(
            replacing: ByteOffset(range.lowerBound) ..< ByteOffset(range.upperBound),
            with: replacement,
        )
        let start = reference.utf8.index(reference.startIndex, offsetBy: range.lowerBound)
        let end = reference.utf8.index(reference.startIndex, offsetBy: range.upperBound)
        reference.replaceSubrange(start ..< end, with: replacement)
        #expect(manager.buffer.string == reference)
    }

    // Re-vend everything and compare per line.
    var vended = ""
    _ = manager.enumerateTextElements(from: manager.documentRange.location, options: []) { element in
        guard let paragraph = element as? NSTextParagraph else { return false }
        vended += paragraph.attributedString.string
        return true
    }
    #expect(vended == reference, "full re-vend must equal reference after edits")
}
