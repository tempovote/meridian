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
