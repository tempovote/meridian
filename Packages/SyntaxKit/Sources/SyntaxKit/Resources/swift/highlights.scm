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
