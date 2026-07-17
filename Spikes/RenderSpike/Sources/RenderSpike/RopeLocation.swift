import AppKit
import DocumentCore

/// An NSTextLocation backed by a rope byte offset. Identity and ordering
/// are byte-offset ordering; TextKit-facing arithmetic (offsetedBy) is
/// UTF-16-unit-based and lives on RopeContentManager, which owns the
/// buffer needed for conversions.
final class RopeLocation: NSObject, NSTextLocation {
    let byte: ByteOffset
    init(_ byte: ByteOffset) { self.byte = byte }

    func compare(_ location: NSTextLocation) -> ComparisonResult {
        guard let other = location as? RopeLocation else {
            preconditionFailure("foreign NSTextLocation \(type(of: location)) passed to RopeLocation.compare")
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
