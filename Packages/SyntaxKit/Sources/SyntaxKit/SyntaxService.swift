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

    /// Parses (or incrementally re-parses, if `edit` and a prior tree
    /// for `documentID` both exist) `snapshot`, runs the language's
    /// highlight query over the whole resulting tree (whole-document
    /// scope this phase — see design spec Decision 4), and returns the
    /// resulting token runs. `version` is echoed back to the caller's
    /// own bookkeeping; this actor does not compare it against anything.
    public func reparse(
        documentID: DocumentID,
        languageID: String,
        snapshot: TextBuffer,
        version: BufferVersion,
        edit: InputEdit?,
    ) async throws -> [TokenRun] {
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
        let namedRanges = cursor.highlights()
        return namedRanges.map { namedRange in
            TokenRun(
                range: ByteOffset(Int(namedRange.tsRange.bytes.lowerBound)) ..<
                    ByteOffset(Int(namedRange.tsRange.bytes.upperBound)),
                type: TokenType(captureName: namedRange.name),
            )
        }
    }
}
