/// Hand-picked, predicate-free subsets of each grammar's real
/// `queries/highlights.scm`, embedded directly (no SPM resource
/// bundling this phase — see the design spec's Decision 3/non-goals).
/// Verified during planning to compile against the real vendored
/// grammars and produce correct captures against real source text.
enum HighlightQueries {
    static let json = """
    (pair key: (_) @string.special.key)
    (string) @string
    (number) @number
    [
      (null)
      (true)
      (false)
    ] @constant.builtin
    (comment) @comment
    """

    static let swift = #"""
    "func" @keyword.function

    [
      "let"
      "var"
      "class"
      "struct"
      "enum"
      "protocol"
      "extension"
    ] @keyword

    [
      (comment)
      (multiline_comment)
    ] @comment

    (line_str_text) @string
    ["\"" "\"\"\""] @string

    [
      (integer_literal)
      (hex_literal)
      (oct_literal)
      (bin_literal)
    ] @number

    (type_identifier) @type
    "return" @keyword
    """#
}
