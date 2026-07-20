/// Typed errors for SyntaxKit. Tree-sitter itself tolerates malformed
/// source (produces ERROR nodes rather than throwing) — these cases
/// cover grammar/query setup failures and the (should-never-happen)
/// case of `ts_parser_parse` itself returning nil.
public enum SyntaxKitError: Error {
    case grammarLoadFailed(languageID: String)
    case queryCompilationFailed(languageID: String, underlying: Error)
    case parseFailed(languageID: String)
}
