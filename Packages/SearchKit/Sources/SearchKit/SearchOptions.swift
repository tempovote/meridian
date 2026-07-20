import Foundation

/// Options controlling search behavior in `SearchKit`.
public struct SearchOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Case-sensitive search.
    public static let caseSensitive = SearchOptions(rawValue: 1 << 0)
    /// Match whole words only.
    public static let wholeWord = SearchOptions(rawValue: 1 << 1)
    /// Treat search query as a regular expression.
    public static let regularExpression = SearchOptions(rawValue: 1 << 2)
}
