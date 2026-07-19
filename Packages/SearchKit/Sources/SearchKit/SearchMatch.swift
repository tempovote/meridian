import DocumentCore
import Foundation

/// Represents a single match result returned by `SearchEngine`.
public struct SearchMatch: Equatable, Sendable {
    /// The byte range of the match within the text buffer.
    public let range: Range<ByteOffset>
    /// The 0-based line index where the match begins.
    public let lineIndex: Int

    public init(range: Range<ByteOffset>, lineIndex: Int) {
        self.range = range
        self.lineIndex = lineIndex
    }
}
