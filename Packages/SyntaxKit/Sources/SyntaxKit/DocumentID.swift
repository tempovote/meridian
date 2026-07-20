import Foundation

/// Caller-supplied stable identity for a document, scoping
/// `SyntaxService`'s per-document parser/tree/token caches. Callers
/// create one `DocumentID` per open document and reuse it across edits.
public struct DocumentID: Hashable, Sendable {
    private let id: UUID

    public init() {
        id = UUID()
    }
}
