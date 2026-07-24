import DocumentCore

/// One foldable region, produced by a grammar's `folds.scm` query.
/// Folding a region hides lines `startLine + 1 ... endLine` (the first
/// line stays visible with a placeholder). Regions spanning fewer than
/// two lines are dropped at extraction; regions sharing a start line are
/// merged keeping the largest (spec: Fold-range computation).
public struct FoldRange: Equatable, Sendable {
    /// Full byte range of the captured node.
    public let range: Range<ByteOffset>
    /// 0-based line of `range.lowerBound`.
    public let startLine: Int
    /// 0-based line of `range.upperBound`.
    public let endLine: Int
    /// 1-based nesting depth among fold ranges (not raw tree depth) —
    /// drives Fold Level N.
    public let depth: Int

    public init(range: Range<ByteOffset>, startLine: Int, endLine: Int, depth: Int) {
        self.range = range
        self.startLine = startLine
        self.endLine = endLine
        self.depth = depth
    }
}

/// Combined output of one parse pass: highlight tokens and fold ranges,
/// both computed from the same tree (spec: "no extra parse").
public struct ParseOutput: Sendable {
    public let tokens: [TokenRun]
    public let folds: [FoldRange]

    public init(tokens: [TokenRun], folds: [FoldRange]) {
        self.tokens = tokens
        self.folds = folds
    }
}
