import DocumentCore

/// A semantic token classification over a byte range of a buffer.
public struct TokenRun: Hashable, Sendable {
    public let range: Range<ByteOffset>
    public let type: TokenType

    public init(range: Range<ByteOffset>, type: TokenType) {
        self.range = range
        self.type = type
    }
}
