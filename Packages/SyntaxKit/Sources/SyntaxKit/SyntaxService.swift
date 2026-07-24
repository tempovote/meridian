import DocumentCore
import Foundation
import SwiftTreeSitter
import TreeSitter

/// Actor-isolated tree-sitter parsing + highlighting service.
/// Receives immutable buffer snapshots, returns version-tagged
/// `[TokenRun]` (ARCHITECTURE §3.4 — the version comparison against
/// "current" is the caller's job, this actor has no independent notion
/// of it).
public actor SyntaxService {
    private let registry: GrammarRegistry
    private var parsers: [DocumentID: Parser] = [:]
    private var trees: [DocumentID: MutableTree] = [:]

    public init(registry: GrammarRegistry = GrammarRegistry()) {
        self.registry = registry
    }

    /// Combined parse: highlight tokens + fold ranges from one tree.
    /// Parses (or incrementally re-parses, if `edit` and a prior tree
    /// for `documentID` both exist) `snapshot`, runs the language's
    /// highlight query over the whole resulting tree (whole-document
    /// scope this phase — see design spec Decision 4), and returns the
    /// resulting token runs plus fold ranges from the same tree (spec:
    /// "no extra parse"). `version` is echoed back to the caller's own
    /// bookkeeping; this actor does not compare it against anything.
    public func parse(
        documentID: DocumentID,
        languageID: String,
        snapshot: TextBuffer,
        version: BufferVersion,
        edit: InputEdit?,
    ) async throws -> ParseOutput {
        let (language, query) = try await registry.grammar(for: languageID)

        let parser: Parser
        if let existing = parsers[documentID] {
            parser = existing
        } else {
            let newParser = Parser()
            try newParser.setLanguage(language)
            parsers[documentID] = newParser
            parser = newParser
        }

        // `edit` is the only thing that tells tree-sitter what changed
        // between the previous parse and `snapshot`. Without it, a cached
        // tree is not a valid incremental base for these (possibly wholly
        // different) bytes — `Tree.edit(_:)` must be called before reuse,
        // per tree-sitter's incremental-parse contract. So: only reuse the
        // cached tree when we actually just edited it; otherwise force a
        // full, from-scratch parse (unconditionally correct, if slower).
        let cachedTree = trees[documentID]
        let treeForParse: MutableTree?
        if let edit, let cachedTree {
            cachedTree.edit(edit)
            treeForParse = cachedTree
        } else {
            treeForParse = nil
        }

        let bytes = Array(snapshot.string.utf8)
        let readBlock: Parser.ReadBlock = { byteIndex, _ in
            guard byteIndex < bytes.count else { return nil }
            return Data(bytes[byteIndex...])
        }

        guard let newTree = parser.parse(tree: treeForParse, encoding: TSInputEncodingUTF8, readBlock: readBlock) else {
            throw SyntaxKitError.parseFailed(languageID: languageID)
        }
        trees[documentID] = newTree

        let cursor = query.execute(in: newTree)
        let namedRanges = cursor
            .filter { Self.predicatesPass(for: $0, snapshot: snapshot) }
            .highlights()
        let tokens = namedRanges.map { namedRange in
            TokenRun(
                range: ByteOffset(Int(namedRange.tsRange.bytes.lowerBound)) ..<
                    ByteOffset(Int(namedRange.tsRange.bytes.upperBound)),
                type: TokenType(captureName: namedRange.name),
            )
        }

        let folds = (try? await extractFolds(languageID: languageID, tree: newTree, snapshot: snapshot)) ?? []
        return ParseOutput(tokens: tokens, folds: folds)
    }

    /// Existing API, preserved so the 22 golden-highlight test files and
    /// incremental-equivalence tests stay untouched.
    public func reparse(
        documentID: DocumentID,
        languageID: String,
        snapshot: TextBuffer,
        version: BufferVersion,
        edit: InputEdit?,
    ) async throws -> [TokenRun] {
        try await parse(
            documentID: documentID, languageID: languageID,
            snapshot: snapshot, version: version, edit: edit,
        ).tokens
    }

    /// Runs the language's fold query (if any) over `tree`, drops
    /// sub-2-line regions, merges same-start-line regions keeping the
    /// largest, and computes 1-based nesting depth by containment.
    private func extractFolds(
        languageID: String, tree: MutableTree, snapshot: TextBuffer,
    ) async throws -> [FoldRange] {
        guard let foldQuery = try await registry.foldQuery(for: languageID) else { return [] }
        let cursor = foldQuery.execute(in: tree)
        var byteRanges: [Range<ByteOffset>] = []
        for match in cursor {
            for capture in match.captures where capture.name == "fold" {
                let byteRange = capture.node.byteRange
                byteRanges.append(
                    ByteOffset(Int(byteRange.lowerBound)) ..< ByteOffset(Int(byteRange.upperBound)),
                )
            }
        }
        // Map to lines, drop < 2-line regions.
        var candidates: [FoldCandidate] = byteRanges.compactMap { range in
            let startLine = snapshot.linePosition(of: range.lowerBound).line
            let endLine = snapshot.linePosition(of: range.upperBound).line
            guard endLine > startLine else { return nil }
            return FoldCandidate(range: range, startLine: startLine, endLine: endLine)
        }
        // Merge same start line, keeping the largest (latest upperBound).
        candidates.sort {
            $0.startLine != $1.startLine
                ? $0.startLine < $1.startLine
                : $0.range.upperBound > $1.range.upperBound
        }
        var merged: [FoldCandidate] = []
        for candidate in candidates where candidate.startLine != merged.last?.startLine {
            merged.append(candidate)
        }
        // Depth by containment: sorted by (start asc, end desc), a stack of
        // enclosing ends gives 1-based nesting depth.
        var result: [FoldRange] = []
        var enclosingEnds: [ByteOffset] = []
        for candidate in merged {
            while let last = enclosingEnds.last, last <= candidate.range.lowerBound {
                enclosingEnds.removeLast()
            }
            enclosingEnds.append(candidate.range.upperBound)
            result.append(FoldRange(
                range: candidate.range,
                startLine: candidate.startLine,
                endLine: candidate.endLine,
                depth: enclosingEnds.count,
            ))
        }
        return result
    }

    /// A fold-query capture mapped to line coordinates, ahead of the final
    /// depth pass. Not `FoldRange` itself: `depth` isn't known until the
    /// containment scan below sees the whole (sorted, merged) sequence.
    private struct FoldCandidate {
        let range: Range<ByteOffset>
        let startLine: Int
        let endLine: Int
    }

    /// Evaluates `match`'s `#match?`/`#eq?`/... predicates against `snapshot`.
    ///
    /// This *cannot* use `QueryMatch.allowed(in:)` + `Predicate.Context`
    /// (SwiftTreeSitter's built-in path): that path slices predicate text
    /// using `Node.range` (`NSRange`), which `Range<UInt32>.range`
    /// (SwiftTreeSitter's `Encoding+Helpers.swift`) computes by
    /// unconditionally halving the tree's raw byte offsets — an assumption
    /// that only holds when the tree was parsed as UTF-16. This service
    /// parses with `TSInputEncodingUTF8` (required so `tsRange.bytes`
    /// above yields true UTF-8 `ByteOffset`s, per ARCHITECTURE's typed
    /// coordinate spaces), so that halving corrupts every predicate's
    /// source range and silently evaluates predicates against the wrong
    /// substring. Bypassing it and reading `Node.byteRange` (the raw,
    /// uncorrupted UTF-8 byte range) plus `TextBuffer.slice` avoids the bug
    /// entirely and keeps the byte-offset conversion inside `TextBuffer`,
    /// per the "raw Int offsets never cross a module boundary" rule.
    private static func predicatesPass(for match: QueryMatch, snapshot: TextBuffer) -> Bool {
        match.predicates.allSatisfy { predicate in
            switch predicate {
            case .set, .generic:
                // Directives / unrecognized predicates never gate the match
                // (mirrors SwiftTreeSitter's own `allowsMatch` behavior).
                true
            case .isNot:
                // Would need `locals.scm` group-membership tracking, which
                // this phase doesn't implement; SwiftTreeSitter's own
                // default `groupMembershipProvider` always returns `false`
                // too, so `#is-not?` is unconditionally satisfied either way.
                true
            case .eq, .notEq, .anyOf, .notAnyOf, .match, .notMatch:
                predicate.captures(in: match).allSatisfy { capture in
                    let byteRange = capture.node.byteRange
                    let text = snapshot.slice(
                        ByteOffset(Int(byteRange.lowerBound)) ..< ByteOffset(Int(byteRange.upperBound)),
                    )
                    return predicate.evalulate(with: text)
                }
            }
        }
    }
}
