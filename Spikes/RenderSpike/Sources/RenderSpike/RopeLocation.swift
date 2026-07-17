import AppKit
import DocumentCore

/// An NSTextLocation backed by a rope byte offset. Identity and ordering
/// are byte-offset ordering; TextKit-facing arithmetic (offsetedBy) is
/// UTF-16-unit-based and lives on RopeContentManager, which owns the
/// buffer needed for conversions.
final class RopeLocation: NSObject, NSTextLocation {
    let byte: ByteOffset
    init(_ byte: ByteOffset) { self.byte = byte }

    // DEVIATION (spike finding, Task 4 — first live NSTextLayoutManager
    // exercise): a single keystroke reliably crashes here. `applyEdit`'s
    // `invalidateLayout(for:)` call reaches
    // `-[NSTextLayoutManager _invalidateLayoutForTextRange:hard:]`, which
    // walks its own internal soft-invalidation bookkeeping and calls
    // `compare(_:)` with a location that is AppKit's private
    // `NSCountableTextLocation`, not a `RopeLocation` — confirmed via crash
    // report backtrace (`RopeLocation.compare(_:)` -> preconditionFailure,
    // called from `__58-[NSTextLayoutManager
    // _invalidateLayoutForTextRange:hard:]_block_invoke.165`, called from
    // `RopeContentManager.applyEdit(replacing:with:)`). This is the mirror
    // image of a second, separate, WORSE crash found while investigating
    // `jump(toLine:)`/`relocateViewport(to:)` (see ViewportView doc comment
    // and the Task 4 report): there, AppKit's OWN
    // `-[NSCountableTextLocation compare:]` throws an uncaught
    // NSInvalidArgumentException when hard-invalidation after a relocated
    // viewport compares against one of OUR `RopeLocation`s. Both crashes
    // are the same root incompatibility — NSTextLayoutManager's internal
    // invalidation machinery is not purely "ask the content manager"; it
    // also maintains its own private location type and compares across the
    // two indiscriminately — from opposite ends: this one is fixable
    // (return a value instead of trapping), the other is not (the throw
    // site is inside AppKit, uncatchable from Swift without NSException
    // bridging this spike does not add). Fix: treat any non-RopeLocation
    // location as coincident (`.orderedSame`) instead of trapping, mirroring
    // `RopeContentManager.offset(from:to:)`'s same-shaped fix. This resolves
    // the typing crash (verified: keystrokes no longer crash, buffer
    // mutates correctly, and the view keeps rendering afterward) but is a
    // best-effort guess with no real ordering information — TextKit's
    // invalidation could, in principle, under- or over-invalidate as a
    // result. Not verified to be artifact-free; flagged for ADR 0009.
    func compare(_ location: NSTextLocation) -> ComparisonResult {
        guard let other = location as? RopeLocation else {
            return .orderedSame
        }
        if byte < other.byte { return .orderedAscending }
        if byte > other.byte { return .orderedDescending }
        return .orderedSame
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RopeLocation else { return false }
        return byte == other.byte
    }

    override var hash: Int { byte.value.hashValue }
    override var description: String { "RopeLocation(\(byte.value))" }
}
