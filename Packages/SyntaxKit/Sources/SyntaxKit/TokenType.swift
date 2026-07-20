/// Normalized semantic token vocabulary that tree-sitter grammar capture
/// names collapse onto (ARCHITECTURE.md §13). Any grammar's captures map
/// through this fixed set, so any grammar works with any theme.
public enum TokenType: String, Sendable, CaseIterable {
    case keyword
    case string
    case comment
    case function
    case type
    case variable
    case property
    case number
    case constant
    case punctuation
    case plain

    /// Maps a raw tree-sitter capture name (e.g. `"keyword.function"`) to
    /// the closest known `TokenType`, stripping dotted suffixes
    /// right-to-left until a match is found (`keyword.control` →
    /// `.keyword`). Falls back to `.plain` if nothing matches.
    public init(captureName: String) {
        var components = captureName.split(separator: ".").map(String.init)
        while !components.isEmpty {
            let candidate = components.joined(separator: ".")
            if let match = TokenType(rawValue: candidate) {
                self = match
                return
            }
            components.removeLast()
        }
        self = .plain
    }
}
