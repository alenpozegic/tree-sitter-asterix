; Structural keywords
[
  "asterix"
  "ref"
  "edition"
  "date"
  "preamble"
  "items"
  "definition"
  "description"
  "remark"
  "group"
  "extended"
  "compound"
  "element"
  "repetitive"
  "explicit"
  "spare"
  "table"
  "string"
  "integer"
  "quantity"
  "bds"
  "uap"
  "uaps"
  "variations"
  "case"
] @keyword

(content_raw) @keyword
(default_case) @keyword
(uap_rfs) @keyword

; Domain identifiers and labels
(item
  (item_name) @property)

(uap_item
  (item_name) @constant)

(item_path
  (item_name) @constant)

(uap_name) @constant

; Numbers and scalar literals
(category_number) @number
(bit_size) @number
(byte_size) @number
(table_key) @number
(case_key) @number
(version) @number
(number) @number
(bds_address) @number

(date_literal) @string.special
(string) @string
(unit) @string.special

[
  "?"
  "fx"
] @constant

; Types and operators
(signedness) @type
(string_type) @type
(explicit_type) @type
(comparison_operator) @operator

; Delimiters and structural punctuation
[
  "("
  ")"
  ","
  "/"
  ":"
  "-"
] @punctuation.delimiter

(extension_spare) @punctuation.delimiter
(compound_spare) @punctuation.delimiter
(uap_spare) @punctuation.delimiter

; Table payloads and documentation text
(table_row
  (text) @string.special)

(preamble
  (text) @comment.documentation)

(definition_block
  (text) @comment.documentation)

(description_block
  (text) @comment.documentation)

(remark_block
  (text) @comment.documentation)

(doc_literal_row_text) @comment.documentation
(doc_value_row_text) @comment.documentation

; Comments
(line_comment) @comment
(block_comment) @comment
