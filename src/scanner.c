#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum TokenType {
  INDENT,
  DEDENT,
  NEWLINE,
};

#define MAX_INDENTS 256
#define SERIALIZED_HEADER_SIZE 18
#define LINEAGE_OFFSET UINT64_C(14695981039346656037)
#define LINEAGE_PRIME UINT64_C(1099511628211)
#define LINEAGE_NEWLINE UINT32_C(0x4e45574c)
#define LINEAGE_INDENT UINT32_C(0x494e444e)
#define LINEAGE_DEDENT UINT32_C(0x4445444e)

typedef struct {
  uint16_t indents[MAX_INDENTS];
  uint16_t indent_count;
  uint16_t pending_dedent_indent;
  uint16_t next_line_indent;
  uint16_t next_line_column;
  bool has_pending_dedent;
  bool has_next_line_indent;
  uint64_t lineage;
} Scanner;

static void advance(TSLexer *lexer) {
  lexer->advance(lexer, false);
}

static bool is_newline(int32_t c) {
  return c == '\n' || c == '\r';
}

static uint64_t lineage_mix_byte(uint64_t lineage, uint8_t value) {
  lineage ^= value;
  lineage *= LINEAGE_PRIME;
  return lineage;
}

static uint64_t lineage_mix_u32(uint64_t lineage, uint32_t value) {
  for (unsigned i = 0; i < 4; i++) {
    lineage = lineage_mix_byte(lineage, (uint8_t)(value & 0xff));
    value >>= 8;
  }
  return lineage;
}

static uint64_t lineage_mix_layout(uint64_t lineage, uint32_t marker,
                                   uint16_t current_indent,
                                   uint16_t target_indent) {
  lineage = lineage_mix_u32(lineage, marker);
  lineage = lineage_mix_u32(lineage, current_indent);
  lineage = lineage_mix_u32(lineage, target_indent);
  return lineage;
}

static void consume_newline(TSLexer *lexer, uint64_t *lineage) {
  if (lexer->lookahead == '\r') {
    *lineage = lineage_mix_u32(*lineage, (uint32_t)'\r');
    advance(lexer);
    if (lexer->lookahead == '\n') {
      *lineage = lineage_mix_u32(*lineage, (uint32_t)'\n');
      advance(lexer);
    }
  } else if (lexer->lookahead == '\n') {
    *lineage = lineage_mix_u32(*lineage, (uint32_t)'\n');
    advance(lexer);
  }
}

static uint16_t current_indent(const Scanner *scanner) {
  return scanner->indents[scanner->indent_count - 1];
}

static void clear_pending_dedent(Scanner *scanner) {
  scanner->pending_dedent_indent = 0;
  scanner->has_pending_dedent = false;
}

static void clear_next_line_indent(Scanner *scanner) {
  scanner->next_line_indent = 0;
  scanner->next_line_column = 0;
  scanner->has_next_line_indent = false;
}

static void reset_scanner(Scanner *scanner) {
  memset(scanner, 0, sizeof(Scanner));
  scanner->indent_count = 1;
  scanner->indents[0] = 0;
  scanner->lineage = LINEAGE_OFFSET;
  clear_pending_dedent(scanner);
  clear_next_line_indent(scanner);
}

static void commit_scanner(Scanner *scanner, const Scanner *next) {
  *scanner = *next;
}

static void write_u16(char *buffer, unsigned *size, uint16_t value) {
  buffer[(*size)++] = (char)(value & 0xff);
  buffer[(*size)++] = (char)((value >> 8) & 0xff);
}

static uint16_t read_u16(const char *buffer, unsigned *size) {
  uint16_t lo = (uint8_t)buffer[(*size)++];
  uint16_t hi = (uint8_t)buffer[(*size)++];
  return (uint16_t)(lo | (hi << 8));
}

static void write_u64(char *buffer, unsigned *size, uint64_t value) {
  for (unsigned i = 0; i < 8; i++) {
    buffer[(*size)++] = (char)(value & 0xff);
    value >>= 8;
  }
}

static uint64_t read_u64(const char *buffer, unsigned *size) {
  uint64_t value = 0;
  for (unsigned i = 0; i < 8; i++) {
    value |= (uint64_t)(uint8_t)buffer[(*size)++] << (i * 8);
  }
  return value;
}

static bool scan_newline(Scanner *scanner, TSLexer *lexer,
                         const bool *valid_symbols) {
  if (!valid_symbols[NEWLINE] || !is_newline(lexer->lookahead)) {
    return false;
  }

  Scanner next = *scanner;
  clear_pending_dedent(&next);
  clear_next_line_indent(&next);

  uint64_t lineage = next.lineage;
  lineage = lineage_mix_u32(lineage, LINEAGE_NEWLINE);
  lineage = lineage_mix_u32(lineage, lexer->get_column(lexer));

  consume_newline(lexer, &lineage);
  lexer->mark_end(lexer);

  uint32_t indent_width = 0;
  uint32_t indent_column = 0;

  for (;;) {
    indent_width = 0;
    indent_column = 0;

    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lineage = lineage_mix_u32(lineage, (uint32_t)lexer->lookahead);
      indent_width += lexer->lookahead == '\t' ? 4u : 1u;
      indent_column++;
      advance(lexer);
    }

    if (!is_newline(lexer->lookahead)) {
      break;
    }

    consume_newline(lexer, &lineage);
    lexer->mark_end(lexer);
  }

  if (!lexer->eof(lexer) && indent_width <= UINT16_MAX &&
      indent_column <= UINT16_MAX) {
    next.next_line_indent = (uint16_t)indent_width;
    next.next_line_column = (uint16_t)indent_column;
    next.has_next_line_indent = true;
  }

  /*
   * Hash the next non-blank physical line without extending the NEWLINE token.
   * Tree-sitter records this lookahead range, so an edit to that line forces
   * the preceding newline state to be reconsidered. The rolling lineage then
   * keeps a malformed incremental scanner history distinct even if its indent
   * stack later returns to the same numerical values as a clean parse.
   *
   * The indentation width and physical whitespace count above are retained as
   * a layout certificate for this exact line. This matters when the generated
   * lexer consumes indentation as `extras` before a later INDENT request: a
   * tab occupies one physical source column but contributes four logical
   * indentation columns under the ASTERIX scanner contract.
   */
  while (!lexer->eof(lexer) && !is_newline(lexer->lookahead)) {
    lineage = lineage_mix_u32(lineage, (uint32_t)lexer->lookahead);
    advance(lexer);
  }

  next.lineage = lineage;
  lexer->result_symbol = NEWLINE;
  commit_scanner(scanner, &next);
  return true;
}

static bool emit_pending_dedent(Scanner *scanner, TSLexer *lexer,
                                const bool *valid_symbols) {
  if (!scanner->has_pending_dedent || !valid_symbols[DEDENT] ||
      scanner->indent_count <= 1) {
    return false;
  }

  Scanner next = *scanner;
  next.indent_count--;
  next.lineage = lineage_mix_layout(next.lineage, LINEAGE_DEDENT,
                                    current_indent(&next),
                                    next.pending_dedent_indent);

  if (current_indent(&next) <= next.pending_dedent_indent) {
    clear_pending_dedent(&next);
  }

  lexer->result_symbol = DEDENT;
  commit_scanner(scanner, &next);
  return true;
}

static bool emit_eof_dedent(Scanner *scanner, TSLexer *lexer,
                            const bool *valid_symbols) {
  if (!lexer->eof(lexer) || !valid_symbols[DEDENT] ||
      scanner->indent_count <= 1) {
    return false;
  }

  Scanner next = *scanner;
  next.indent_count--;
  clear_pending_dedent(&next);
  clear_next_line_indent(&next);
  next.lineage = lineage_mix_layout(next.lineage, LINEAGE_DEDENT,
                                    current_indent(&next), 0);

  lexer->result_symbol = DEDENT;
  commit_scanner(scanner, &next);
  return true;
}

static bool measure_line_indent(TSLexer *lexer, uint16_t *indent) {
  uint32_t width = 0;

  while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
    width += lexer->lookahead == '\t' ? 4u : 1u;
    if (width > UINT16_MAX) {
      return false;
    }
    advance(lexer);
  }

  if (is_newline(lexer->lookahead) || lexer->eof(lexer)) {
    return false;
  }

  *indent = (uint16_t)width;
  lexer->mark_end(lexer);
  return true;
}

static bool scan_layout(Scanner *scanner, TSLexer *lexer,
                        const bool *valid_symbols) {
  if (!(valid_symbols[INDENT] || valid_symbols[DEDENT])) {
    return false;
  }

  const uint32_t column = lexer->get_column(lexer);
  uint16_t target_indent = 0;
  bool measured_from_line_start = false;
  bool certified_after_extras = false;

  if (column == 0) {
    if (!measure_line_indent(lexer, &target_indent)) {
      return false;
    }
    measured_from_line_start = true;
  } else if (scanner->has_next_line_indent &&
             column == scanner->next_line_column) {
    /*
     * Leading indentation can already have been consumed as a normal `extra`.
     * The preceding successful NEWLINE hashed this exact physical line and
     * recorded both its raw whitespace count and logical tab-expanded width.
     * At that exact content boundary the certificate is stronger evidence than
     * get_column(), whose codepoint count cannot represent tab width. Keep the
     * certificate for the whole physical line: after an INDENT, Tree-sitter can
     * immediately call the scanner again at the same boundary with
     * DEDENT + NEWLINE valid, and that call must see the same logical indent.
     */
    target_indent = scanner->next_line_indent;
    certified_after_extras = true;
  } else {
    /*
     * Normal lexing may already have consumed leading spaces as extras before
     * a later parser state requests DEDENT. Keep this fallback one-way: never
     * synthesize an INDENT from a non-zero column without the exact line
     * certificate above, and avoid the all-token recovery state when INDENT is
     * also valid.
     */
    if (!valid_symbols[DEDENT] || valid_symbols[INDENT] ||
        column > UINT16_MAX) {
      return false;
    }

    target_indent = (uint16_t)column;
    if (target_indent >= current_indent(scanner)) {
      return false;
    }
  }

  const uint16_t previous_indent = current_indent(scanner);

  if (target_indent > previous_indent) {
    if ((!measured_from_line_start && !certified_after_extras) ||
        !valid_symbols[INDENT] || scanner->indent_count >= MAX_INDENTS) {
      return false;
    }

    Scanner next = *scanner;
    next.indents[next.indent_count++] = target_indent;
    clear_pending_dedent(&next);
    next.lineage = lineage_mix_layout(next.lineage, LINEAGE_INDENT,
                                      target_indent, target_indent);

    lexer->result_symbol = INDENT;
    commit_scanner(scanner, &next);
    return true;
  }

  if (target_indent < previous_indent) {
    if (!valid_symbols[DEDENT] || scanner->indent_count <= 1) {
      return false;
    }

    Scanner next = *scanner;
    next.indent_count--;

    if (target_indent < current_indent(&next)) {
      next.pending_dedent_indent = target_indent;
      next.has_pending_dedent = true;
    } else {
      clear_pending_dedent(&next);
    }

    next.lineage = lineage_mix_layout(next.lineage, LINEAGE_DEDENT,
                                      current_indent(&next), target_indent);
    lexer->result_symbol = DEDENT;
    commit_scanner(scanner, &next);
    return true;
  }

  return false;
}

void *tree_sitter_asterix_spec_external_scanner_create(void) {
  Scanner *scanner = calloc(1, sizeof(Scanner));
  reset_scanner(scanner);
  return scanner;
}

void tree_sitter_asterix_spec_external_scanner_destroy(void *payload) {
  free(payload);
}

void tree_sitter_asterix_spec_external_scanner_reset(void *payload) {
  reset_scanner((Scanner *)payload);
}

unsigned tree_sitter_asterix_spec_external_scanner_serialize(void *payload,
                                                        char *buffer) {
  Scanner *scanner = (Scanner *)payload;
  const unsigned required_size =
      SERIALIZED_HEADER_SIZE + (unsigned)scanner->indent_count * 2;

  if (scanner->indent_count == 0 || scanner->indent_count > MAX_INDENTS ||
      required_size > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
    return 0;
  }

  unsigned size = 0;
  write_u16(buffer, &size, scanner->indent_count);
  write_u16(buffer, &size, scanner->pending_dedent_indent);
  write_u16(buffer, &size, scanner->next_line_indent);
  write_u16(buffer, &size, scanner->next_line_column);
  buffer[size++] = scanner->has_pending_dedent ? 1 : 0;
  buffer[size++] = scanner->has_next_line_indent ? 1 : 0;
  write_u64(buffer, &size, scanner->lineage);

  for (uint16_t i = 0; i < scanner->indent_count; i++) {
    write_u16(buffer, &size, scanner->indents[i]);
  }

  return size;
}

void tree_sitter_asterix_spec_external_scanner_deserialize(void *payload,
                                                      const char *buffer,
                                                      unsigned length) {
  Scanner *scanner = (Scanner *)payload;
  Scanner restored;
  reset_scanner(&restored);

  if (length == 0) {
    commit_scanner(scanner, &restored);
    return;
  }

  if (length < SERIALIZED_HEADER_SIZE) {
    commit_scanner(scanner, &restored);
    return;
  }

  unsigned size = 0;
  const uint16_t indent_count = read_u16(buffer, &size);
  const uint16_t pending_dedent_indent = read_u16(buffer, &size);
  const uint16_t next_line_indent = read_u16(buffer, &size);
  const uint16_t next_line_column = read_u16(buffer, &size);
  const bool has_pending_dedent = buffer[size++] != 0;
  const bool has_next_line_indent = buffer[size++] != 0;
  const uint64_t lineage = read_u64(buffer, &size);
  const unsigned expected_size =
      SERIALIZED_HEADER_SIZE + (unsigned)indent_count * 2;

  if (indent_count == 0 || indent_count > MAX_INDENTS ||
      length != expected_size) {
    commit_scanner(scanner, &restored);
    return;
  }

  restored.indent_count = indent_count;
  restored.pending_dedent_indent = pending_dedent_indent;
  restored.next_line_indent = next_line_indent;
  restored.next_line_column = next_line_column;
  restored.has_pending_dedent = has_pending_dedent;
  restored.has_next_line_indent = has_next_line_indent;
  restored.lineage = lineage;

  for (uint16_t i = 0; i < indent_count; i++) {
    restored.indents[i] = read_u16(buffer, &size);
  }

  bool valid_state = restored.indents[0] == 0 && restored.lineage != 0;
  for (uint16_t i = 1; valid_state && i < restored.indent_count; i++) {
    if (restored.indents[i] <= restored.indents[i - 1]) {
      valid_state = false;
    }
  }

  if (valid_state && restored.has_pending_dedent) {
    if (restored.indent_count <= 1 ||
        restored.pending_dedent_indent >= current_indent(&restored)) {
      valid_state = false;
    }
  }

  if (valid_state && restored.has_next_line_indent) {
    if (restored.next_line_column > restored.next_line_indent) {
      valid_state = false;
    }
  }

  if (!valid_state) {
    reset_scanner(&restored);
  } else {
    if (!restored.has_pending_dedent) {
      clear_pending_dedent(&restored);
    }
    if (!restored.has_next_line_indent) {
      clear_next_line_indent(&restored);
    }
  }

  commit_scanner(scanner, &restored);
}

bool tree_sitter_asterix_spec_external_scanner_scan(void *payload, TSLexer *lexer,
                                               const bool *valid_symbols) {
  Scanner *scanner = (Scanner *)payload;

  if (scanner->has_pending_dedent &&
      emit_pending_dedent(scanner, lexer, valid_symbols)) {
    return true;
  }

  if (lexer->eof(lexer)) {
    return emit_eof_dedent(scanner, lexer, valid_symbols);
  }

  if (scan_newline(scanner, lexer, valid_symbols)) {
    return true;
  }

  return scan_layout(scanner, lexer, valid_symbols);
}
