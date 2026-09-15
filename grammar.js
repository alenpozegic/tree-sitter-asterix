/**
 * @file Tree-sitter grammar for ASTERIX .ast specification files.
 * @author Alen Požegić
 * @license BSD-3-Clause
 */

const documentationBlock = ($, keyword) => seq(
  keyword,
  $._newline,
  $._indent,
  repeat1($._text_block_line),
  repeat1($._dedent),
);

module.exports = grammar({
  name: "asterix",

  externals: $ => [
    $._indent,
    $._dedent,
    $._newline,
  ],

  extras: $ => [
    /[ \t]+/,
    $.line_comment,
    $.block_comment,
  ],

  word: $ => $.identifier,

  conflicts: $ => [
    [$.definition_block],
    [$.description_block],
    [$.remark_block],
    [$.doc_literal_row, $._doc_literal_row_plain],
  ],

  rules: {
    source_file: $ => seq(
      repeat($._newline),
      choice($.basic_category, $.ref_spec),
      repeat($._newline),
    ),

    basic_category: $ => seq(
      $.category_header,
      $._newline,
      $.edition,
      $._newline,
      $.date,
      optional(seq($._newline, $.preamble)),
      repeat($._newline),
      $.items_block,
      repeat($._newline),
      $._uap_section,
    ),

    ref_spec: $ => seq(
      $.ref_header,
      $._newline,
      $.edition,
      $._newline,
      $.date,
      repeat($._newline),
      $.compound,
    ),

    category_header: $ => seq(
      "asterix",
      $.category_number,
      $.string,
    ),

    ref_header: $ => seq(
      "ref",
      $.category_number,
      $.string,
    ),

    edition: $ => seq(
      "edition",
      $.version,
    ),

    date: $ => seq(
      "date",
      $.date_literal,
    ),

    preamble: $ => prec(1, seq(
      "preamble",
      $._newline,
      $._indent,
      repeat1($._text_block_line),
      repeat1($._dedent),
    )),

    items_block: $ => seq(
      "items",
      $._newline,
      $._indent,
      repeat(choice($._newline, $.item)),
      $._dedent,
    ),

    item: $ => seq(
      $.item_name,
      $.string,
      $._newline,
      $._indent,
      repeat(choice(
        $._newline,
        $.definition_block,
        $.description_block,
        $.remark_block,
        $._variation,
        $.spare,
      )),
      $._dedent,
    ),

    definition_block: $ => documentationBlock($, "definition"),

    description_block: $ => documentationBlock($, "description"),

    remark_block: $ => documentationBlock($, "remark"),

    _text_block_line: $ => choice(
      $._doc_value_list_block,
      $._doc_literal_dedent_prose_block,
      $._doc_dedent_prose_block,
      $._newline,
      $._indent,
      seq(alias($._numbered_text, $.text), $._newline),
      seq(repeat1($._dedent), alias($._numbered_text, $.text), $._newline),
      seq(alias($._bullet_text, $.text), $._newline),
      seq(repeat1($._dedent), alias($._bullet_text, $.text), $._newline),
      seq(repeat1($._dedent), alias($._doc_parenthetical_text, $.text), $._newline),
      seq(repeat1($._dedent), alias($._doc_code_note_text, $.text), $._newline),
      $._doc_literal_intro,
      $.doc_literal_row,
      $.doc_value_row,
      prec.right(1, seq(repeat1($._dedent), alias($._doc_label_text, $.text), $._newline)),
      seq($.text, $._newline),
    ),

    _doc_literal_intro: $ => prec.right(2, seq(
      repeat1($._dedent),
      alias($._doc_literal_marker_text, $.text),
      $._newline,
    )),

    doc_literal_row: $ => prec.right(2, seq(
      optional(repeat1($._dedent)),
      $.doc_literal_row_text,
      $._newline,
    )),

    doc_value_row: $ => prec.right(2, seq(
      $.doc_value_row_text,
      $._newline,
    )),

    _doc_value_list_block: $ => prec.right(3, seq(
      $._indent,
      repeat1($.doc_value_row),
      repeat1($._dedent),
      alias($._doc_continuation_text, $.text),
      $._newline,
      repeat(seq(alias($._doc_continuation_rest_text, $.text), $._newline)),
    )),

    _doc_literal_dedent_prose_block: $ => prec.right(4, seq(
      repeat1(alias($._doc_literal_row_plain, $.doc_literal_row)),
      repeat1($._dedent),
      alias(choice($._doc_parenthetical_text, $._doc_code_note_text, $._doc_continuation_text), $.text),
      $._newline,
      repeat(seq(alias($._doc_continuation_rest_text, $.text), $._newline)),
    )),

    _doc_literal_row_plain: $ => prec.right(2, seq(
      $.doc_literal_row_text,
      $._newline,
    )),

    _doc_dedent_prose_block: $ => prec.right(2, seq(
      repeat1($._dedent),
      alias($._doc_continuation_text, $.text),
      $._newline,
      repeat(seq(alias($._doc_continuation_rest_text, $.text), $._newline)),
    )),

    _variation: $ => choice(
      $.element,
      $.group,
      $.extended,
      $.repetitive,
      $.explicit,
      $.compound,
      $.dependent_variation,
    ),

    element: $ => seq(
      "element",
      $.bit_size,
      $._newline,
      $._indent,
      $._content,
      optional($._newline),
      $._dedent,
    ),

    group: $ => seq(
      "group",
      $._newline,
      $._indent,
      repeat(choice($._newline, $.item, $.spare)),
      $._dedent,
    ),

    extended: $ => seq(
      "extended",
      $._newline,
      $._indent,
      repeat(choice($._newline, $.item, $.spare, $.extension_spare)),
      $._dedent,
    ),

    compound: $ => seq(
      "compound",
      optional(choice($.byte_size, "fx")),
      $._newline,
      $._indent,
      repeat(choice($._newline, $.item, $.compound_spare)),
      $._dedent,
    ),

    dependent_variation: $ => seq(
      "case",
      choice($.item_path, $.item_path_tuple),
      $._newline,
      $._indent,
      repeat(choice($._newline, $.variation_case)),
      $._dedent,
    ),

    variation_case: $ => seq(
      choice($.case_key, $.case_key_tuple, $.default_case),
      ":",
      $._newline,
      $._indent,
      $._variation,
      optional($._newline),
      $._dedent,
    ),

    repetitive: $ => seq(
      "repetitive",
      choice($.byte_size, "fx"),
      $._newline,
      $._indent,
      $._variation,
      optional($._newline),
      $._dedent,
    ),

    explicit: $ => seq(
      "explicit",
      optional($.explicit_type),
    ),

    spare: $ => seq(
      "spare",
      $.bit_size,
    ),

    extension_spare: _ => "-",

    compound_spare: _ => "-",

    _content: $ => choice(
      $.content_raw,
      $.content_table,
      $.content_string,
      $.content_integer,
      $.content_quantity,
      $.content_bds,
      $.content_dependent,
    ),

    content_raw: _ => "raw",

    content_table: $ => seq(
      "table",
      $._newline,
      $._indent,
      repeat1(seq($.table_row, optional($._newline))),
      $._dedent,
    ),

    table_row: $ => seq(
      $.table_key,
      ":",
      optional($.text),
    ),

    content_string: $ => seq(
      "string",
      $.string_type,
    ),

    content_integer: $ => seq(
      $.signedness,
      "integer",
      repeat($.constraint),
    ),

    content_quantity: $ => seq(
      $.signedness,
      "quantity",
      $.number,
      $.unit,
      repeat($.constraint),
    ),

    content_bds: $ => seq(
      "bds",
      optional(choice("?", $.bds_address)),
    ),

    content_dependent: $ => seq(
      "case",
      choice($.item_path, $.item_path_tuple),
      $._newline,
      $._indent,
      repeat(choice($._newline, $.content_case)),
      $._dedent,
    ),

    content_case: $ => seq(
      choice($.case_key, $.case_key_tuple, $.default_case),
      ":",
      $._newline,
      $._indent,
      $._content,
      optional($._newline),
      $._dedent,
    ),

    uap_block: $ => seq(
      "uap",
      $._newline,
      $._indent,
      repeat(choice($._newline, $.uap_item, $.uap_spare, $.uap_rfs)),
      $._dedent,
    ),

    _uap_section: $ => choice(
      $.uap_block,
      $.uaps_block,
    ),

    uaps_block: $ => seq(
      "uaps",
      $._newline,
      $._indent,
      $.uap_variations_block,
      repeat($._newline),
      optional($.uap_case_block),
      $._dedent,
    ),

    uap_variations_block: $ => seq(
      "variations",
      $._newline,
      $._indent,
      repeat(choice($._newline, $.uap_variation)),
      $._dedent,
    ),

    uap_variation: $ => seq(
      $.uap_name,
      $._newline,
      $._indent,
      repeat(choice($._newline, $.uap_item, $.uap_spare, $.uap_rfs)),
      $._dedent,
    ),

    uap_case_block: $ => seq(
      "case",
      $.item_path,
      $._newline,
      $._indent,
      repeat(choice($._newline, $.uap_case_row)),
      $._dedent,
    ),

    uap_case_row: $ => seq(
      $.case_key,
      ":",
      $.uap_name,
    ),

    uap_item: $ => $.item_name,

    uap_spare: _ => "-",

    uap_rfs: _ => "rfs",

    item_path: $ => seq(
      $.item_name,
      repeat(seq("/", $.item_name)),
    ),

    item_path_tuple: $ => seq(
      "(",
      $.item_path,
      repeat(seq(",", $.item_path)),
      ")",
    ),

    category_number: _ => /\d{3}/,

    item_name: _ => /[A-Za-z0-9_]+/,

    bit_size: _ => /\d+/,

    byte_size: _ => /\d+/,

    table_key: _ => /\d+/,

    case_key: _ => /\d+/,

    case_key_tuple: $ => seq(
      "(",
      $.case_key,
      repeat(seq(",", $.case_key)),
      ")",
    ),

    default_case: _ => "default",

    uap_name: _ => /[A-Za-z0-9-]+/,

    version: _ => /\d+\.\d+/,

    date_literal: _ => /\d{4}-\d{2}-\d{2}/,

    signedness: _ => choice("signed", "unsigned"),

    string_type: _ => choice("ascii", "icao", "octal"),

    explicit_type: _ => choice("re", "sp"),

    bds_address: _ => /[0-9A-Fa-f]{2}/,

    constraint: $ => seq(
      $.comparison_operator,
      $.number,
    ),

    comparison_operator: _ => choice("==", "/=", ">=", ">", "<=", "<"),

    number: _ => /-?\d+(\^-?\d+)?(\/-?\d+(\^-?\d+)?)*/,

    unit: _ => token(seq(
      "\"",
      repeat(choice(/[^"\\]/, /\\./)),
      "\"",
    )),

    string: _ => token(seq(
      "\"",
      repeat(choice(/[^"\\]/, /\\./)),
      "\"",
    )),

    text: _ => token(prec(1, /[^\r\n]+/)),

    _numbered_text: _ => token(prec(2, /\d+\.[^\r\n]*/)),

    _bullet_text: _ => token(prec(2, /[-*][^\r\n]*/)),

    _doc_label_text: _ => token(prec(2, choice(
      /[A-Z][A-Za-z0-9 _/()#-]*:/,
      /NOTE - [^\r\n:]+:?/,
    ))),

    _doc_parenthetical_text: _ => token(prec(2, /\([^\r\n]+\)[^\r\n]*/)),

    _doc_code_note_text: _ => token(prec(2, /[A-Z0-9]{1,8}\s+\d+\s*=\s*[^\r\n]*/)),

    _doc_literal_marker_text: _ => token(prec(3, /[^\r\n]*::[^\r\n]*/)),

    doc_literal_row_text: _ => token(prec(3, choice(
      seq("I", /\d{3}/, "/", /[^\r\n]*/),
      /[^ \t\r\n][^\r\n]*[ \t]{2,}[^ \t\r\n][^\r\n]*/,
    ))),

    doc_value_row_text: _ => token(prec(3, /\d+\s*=\s*[^\r\n]*/)),

    _doc_continuation_text: _ => token(prec(2, /[A-Z][a-z][^\r\n]*/)),

    _doc_continuation_rest_text: _ => token(prec(2, /[A-Za-z][^\r\n]*/)),

    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,

    line_comment: _ => token(seq("//", /[^\r\n]*/)),

    block_comment: _ => token(seq(
      "/*",
      /[^*]*\*+([^/*][^*]*\*+)*/,
      "/",
    )),
  },
});
