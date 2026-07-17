import AppKit
import DocumentCore

/// NSTextContentManager backed by an immutable TextBuffer snapshot.
/// Vends one NSTextParagraph per buffer line, on demand — the document
/// never exists as a single NSAttributedString.
///
/// SPIKE CONTRACT: every place the real TextKit 2 API forces a deviation
/// from this starting shape is a finding for ADR 0009. Log it.
///
/// DEVIATION (spike finding — see the Task 2 report for the full trace,
/// revised after code review): the class is `@MainActor`, as the brief
/// specified, but that annotation cannot be enforced at the
/// `NSTextElementProvider` override points. Every requirement overridden
/// here (`documentRange`, `enumerateTextElements`, `location(_:offsetBy:)`,
/// `offset(from:to:)`, `replaceContents`) comes from an Objective-C
/// protocol/superclass with no actor-isolation annotation, so Swift keeps
/// each override `nonisolated` regardless of the class-level `@MainActor`
/// — a class annotation does not propagate onto overrides of an
/// unisolated superclass member — and `NSTextRange`/`NSTextLocation` are
/// non-`Sendable` (`NSTextRange`'s `Sendable` conformance is explicitly
/// marked unavailable), which rules out bridging those overrides back to
/// actor isolation via `MainActor.assumeIsolated`. `@MainActor` still
/// governs any future non-override methods added to this class (e.g.
/// Task 3's mutation entry points, if they aren't themselves protocol
/// overrides). The `buffer` property is `nonisolated(unsafe)` so the
/// `nonisolated` overrides can read it directly; the private plain-Swift
/// helpers they call (`paragraphByteRange(forLine:)`, `paragraph(forLine:)`,
/// `assertMainThreadContract()`) are marked `nonisolated` to match. None
/// of this reflects a real data race: TextKit 2 invokes
/// `NSTextElementProvider` synchronously, on whatever thread owns the
/// associated `NSTextLayoutManager` (the main thread, for app UI), and
/// this spike's own tests call every method directly from `@MainActor`
/// test functions. Thread-safety is the documented calling-convention
/// contract TextKit itself relies on, backed by a `Thread.isMainThread`
/// assertion in every mutating/reading entry point as a cheap runtime
/// tripwire — note that assertion strips out of release builds, so it is
/// a debug-time guard, not a production safety net.
@MainActor
final class RopeContentManager: NSTextContentManager {
    nonisolated(unsafe) private(set) var buffer: TextBuffer

    /// Monospace rendering attributes shared by every paragraph.
    ///
    /// DEVIATION: any global (`static let`) whose type isn't provably
    /// `Sendable` — `[NSAttributedString.Key: Any]` here, because `Any`
    /// can't be — is flagged under Swift 6 strict concurrency
    /// ("not concurrency-safe... may have shared mutable state"),
    /// independent of the class's own isolation. It's immutable and
    /// read-only after initialization, so `nonisolated(unsafe)` — the
    /// value never actually mutates after this literal — is the correct
    /// escape hatch, not a design flaw to paper over.
    nonisolated(unsafe) static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.textColor,
    ]

    init(buffer: TextBuffer) {
        self.buffer = buffer
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Cheap tripwire for the documented-but-unenforced single-threaded
    /// contract (see the type-level DEVIATION note): every
    /// NSTextElementProvider entry point is expected to run on the same
    /// thread TextKit itself uses for layout (main, for app UI). This
    /// traps loudly instead of silently racing if that's ever violated.
    private nonisolated static func assertMainThreadContract() {
        assert(Thread.isMainThread, "RopeContentManager accessed off the main thread — TextKit's own single-thread contract was violated")
    }

    // MARK: NSTextElementProvider

    override var documentRange: NSTextRange {
        Self.assertMainThreadContract()
        guard let range = NSTextRange(
            location: RopeLocation(ByteOffset(0)),
            end: RopeLocation(ByteOffset(buffer.utf8Count)),
        ) else {
            preconditionFailure("documentRange construction failed")
        }
        return range
    }

    /// Element range for the line containing `byte` (or starting at it):
    /// line content plus trailing newline; the final line has none.
    private nonisolated func paragraphByteRange(forLine line: Int) -> Range<ByteOffset> {
        let content = buffer.byteRange(ofLine: line)
        let end = min(content.upperBound.value + 1, buffer.utf8Count)
        return content.lowerBound ..< ByteOffset(end)
    }

    private nonisolated func paragraph(forLine line: Int) -> NSTextParagraph {
        let range = paragraphByteRange(forLine: line)
        let content = buffer.slice(range.lowerBound ..< range.upperBound)
        let attributed = NSAttributedString(string: content, attributes: Self.attributes)
        let paragraph = NSTextParagraph(attributedString: attributed)
        return paragraph
    }

    override func enumerateTextElements(
        from textLocation: NSTextLocation?,
        options: NSTextContentManager.EnumerationOptions = [],
        using block: (NSTextElement) -> Bool,
    ) -> NSTextLocation? {
        Self.assertMainThreadContract()
        let startByte: ByteOffset
        if let rope = textLocation as? RopeLocation {
            startByte = rope.byte
        } else if textLocation == nil {
            startByte = ByteOffset(0)
        } else {
            preconditionFailure("foreign location \(String(describing: textLocation))")
        }
        let reverse = options.contains(.reverse)

        // Forward enumeration starting at or beyond the end of a
        // non-empty buffer has nothing left to vend — return immediately
        // rather than falling into the clamp below, which would
        // otherwise re-derive a line from the clamped (last valid) byte
        // and re-vend it. On an empty buffer, start == end == 0 is also
        // the start of its one empty paragraph (see below), so this must
        // not fire there — the `buffer.utf8Count > 0` guard keeps that
        // case falling through to the loop.
        if !reverse, buffer.utf8Count > 0, startByte.value >= buffer.utf8Count {
            return textLocation
        }

        // Clamp: enumeration may start at documentRange.end.
        let clamped = min(startByte.value, max(buffer.utf8Count - 1, 0))
        var line = buffer.linePosition(of: ByteOffset(clamped)).line
        if reverse, startByte.value == buffer.utf8Count {
            line = buffer.lineCount - 1
        }
        var lastEnd: NSTextLocation? = textLocation
        while line >= 0, line < buffer.lineCount {
            let byteRange = paragraphByteRange(forLine: line)
            let element = paragraph(forLine: line)
            guard let elementRange = NSTextRange(
                location: RopeLocation(byteRange.lowerBound),
                end: RopeLocation(byteRange.upperBound),
            ) else { preconditionFailure("elementRange construction failed") }
            element.elementRange = elementRange
            if !block(element) { return lastEnd }
            lastEnd = reverse ? elementRange.location : elementRange.endLocation
            line += reverse ? -1 : 1
        }
        return lastEnd
    }

    // DEVIATION (spike finding): the brief's method name `location(_:offsetedBy:)`
    // does not exist on NSTextContentManager/NSTextElementProvider and fails
    // to compile ("argument labels ... do not match those of overridden
    // method 'location(_:offsetBy:)'"). The real Objective-C selector is
    // `locationFromLocation:withOffset:`, which Swift imports as
    // `location(_:offsetBy:)`. Implemented against the real name.
    override func location(_ location: NSTextLocation, offsetBy offset: Int) -> NSTextLocation? {
        Self.assertMainThreadContract()
        guard let rope = location as? RopeLocation else { return nil }
        // TextKit's offset unit within elements is UTF-16 code units
        // (NSAttributedString length semantics). Convert byte→utf16, step,
        // convert back. If TextKit ever lands inside a surrogate pair,
        // DocumentCore's precondition will trap loudly — that trap is a
        // spike finding, not a bug to paper over.
        let utf16 = buffer.utf16Offset(of: rope.byte).value + offset
        guard utf16 >= 0, utf16 <= buffer.utf16Count else { return nil }
        return RopeLocation(buffer.byteOffset(of: UTF16Offset(utf16)))
    }

    override func offset(from: NSTextLocation, to: NSTextLocation) -> Int {
        Self.assertMainThreadContract()
        guard let a = from as? RopeLocation, let b = to as? RopeLocation else {
            preconditionFailure("foreign locations in offset(from:to:)")
        }
        return buffer.utf16Offset(of: b.byte).value - buffer.utf16Offset(of: a.byte).value
    }

    override func replaceContents(in range: NSTextRange, with textElements: [NSTextElement]?) {
        // Read-only until Task 3.
        preconditionFailure("editing arrives in Task 3")
    }
}
