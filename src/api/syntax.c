#define PCRE2_CODE_UNIT_WIDTH 8
#include <SDL3/SDL.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pcre2.h>
#include "syntax.h"


typedef struct {
  char *source;
  size_t source_length;
  pcre2_code *end_regex;
  char *type;
  unsigned char escape;
} SyntaxPattern;


typedef struct {
  char *text;
  size_t length;
  char *type;
  uint64_t hash;
} SyntaxSymbol;


struct DocumentSyntax {
  SyntaxPattern *patterns;
  size_t pattern_count;
  pcre2_code *token_regex;
  SyntaxSymbol *symbols;
  size_t symbol_count;
  pcre2_match_data *match_data;
};


static void syntax_pattern_destroy(SyntaxPattern *pattern) {
  SDL_free(pattern->source);
  pcre2_code_free(pattern->end_regex);
  SDL_free(pattern->type);
  *pattern = (SyntaxPattern) { 0 };
}


static void syntax_symbol_destroy(SyntaxSymbol *symbol) {
  SDL_free(symbol->text);
  SDL_free(symbol->type);
  *symbol = (SyntaxSymbol) { 0 };
}


static void syntax_destroy(DocumentSyntax *syntax) {
  for (size_t i = 0; i < syntax->pattern_count; i++) {
    syntax_pattern_destroy(&syntax->patterns[i]);
  }
  for (size_t i = 0; i < syntax->symbol_count; i++) {
    syntax_symbol_destroy(&syntax->symbols[i]);
  }
  SDL_free(syntax->patterns);
  SDL_free(syntax->symbols);
  pcre2_code_free(syntax->token_regex);
  pcre2_match_data_free(syntax->match_data);
  *syntax = (DocumentSyntax) { 0 };
}


DocumentSyntax *document_syntax_check(lua_State *L, int index) {
  return luaL_checkudata(L, index, API_TYPE_DOCUMENT_SYNTAX);
}


static pcre2_code *try_compile_regex(
  const char *regex,
  size_t length,
  int *error_code,
  PCRE2_SIZE *error_offset
) {
  return pcre2_compile(
    (PCRE2_SPTR) regex,
    (PCRE2_SIZE) length,
    0,
    error_code,
    error_offset,
    NULL);
}


static const char *regex_error_message(
  int error_code, char *buffer, size_t buffer_size
) {
  int result = pcre2_get_error_message(
    error_code, (PCRE2_UCHAR *) buffer, (PCRE2_SIZE) buffer_size);
  if (result < 0) {
    SDL_strlcpy(buffer, "unknown PCRE2 error", buffer_size);
  }
  return buffer;
}


static SDL_NORETURN void raise_regex_error(
  lua_State *L,
  const char *description,
  int error_code,
  PCRE2_SIZE error_offset
) {
  char message[256];
  luaL_error(
    L,
    "invalid %s at byte %I: %s",
    description,
    (lua_Integer) error_offset + 1,
    regex_error_message(error_code, message, sizeof(message)));
  abort();
}


static SDL_NORETURN void raise_out_of_memory(lua_State *L) {
  luaL_error(L, "out of memory while compiling syntax");
  abort();
}


static pcre2_code *compile_regex(lua_State *L, const char *regex, size_t length) {
  int error_code = 0;
  PCRE2_SIZE error_offset = 0;
  pcre2_code *code = try_compile_regex(
    regex, length, &error_code, &error_offset);
  if (!code) {
    raise_regex_error(L, "tokenizer regex", error_code, error_offset);
  }
  return code;
}


static pcre2_code *compile_owned_regex(
  lua_State *L, char *regex, size_t length
) {
  int error_code = 0;
  PCRE2_SIZE error_offset = 0;
  pcre2_code *code = try_compile_regex(
    regex, length, &error_code, &error_offset);
  SDL_free(regex);
  if (!code) {
    raise_regex_error(
      L, "combined tokenizer regex", error_code, error_offset);
  }
  return code;
}


static char *duplicate_bytes(lua_State *L, const char *value, size_t length) {
  if (length == SIZE_MAX) { raise_out_of_memory(L); }
  char *copy = SDL_malloc(length + 1);
  if (!copy) { raise_out_of_memory(L); }
  if (length) { SDL_memcpy(copy, value, length); }
  copy[length] = '\0';
  return copy;
}


static char *duplicate_lua_string(lua_State *L, int index, size_t *length) {
  const char *value = luaL_checklstring(L, index, length);
  return duplicate_bytes(L, value, *length);
}


static void compile_pattern(
  lua_State *L, SyntaxPattern *result, int pattern_index
) {
  lua_getfield(L, pattern_index, "type");
  size_t type_length = 0;
  result->type = duplicate_lua_string(L, -1, &type_length);
  (void) type_length;
  lua_pop(L, 1);

  lua_getfield(L, pattern_index, "pattern");
  if (lua_type(L, -1) == LUA_TSTRING) {
    const char *regex = lua_tolstring(L, -1, &result->source_length);
    result->source = duplicate_bytes(L, regex, result->source_length);
  } else {
    luaL_checktype(L, -1, LUA_TTABLE);
    lua_geti(L, -1, 1);
    size_t start_length = 0;
    const char *start = luaL_checklstring(L, -1, &start_length);
    result->source = duplicate_bytes(L, start, start_length);
    result->source_length = start_length;
    lua_pop(L, 1);

    lua_geti(L, -1, 2);
    size_t end_length = 0;
    const char *end = luaL_checklstring(L, -1, &end_length);
    result->end_regex = compile_regex(L, end, end_length);
    lua_pop(L, 1);

    lua_geti(L, -1, 3);
    if (!lua_isnil(L, -1)) {
      size_t escape_length = 0;
      const char *escape = luaL_checklstring(L, -1, &escape_length);
      if (escape_length != 1) {
        luaL_error(L, "tokenizer escape must be one byte");
      }
      result->escape = (unsigned char) escape[0];
    }
    lua_pop(L, 1);
  }
  lua_pop(L, 1);

  pcre2_code *validation = compile_regex(
    L, result->source, result->source_length);
  PCRE2_SIZE minimum_length = 0;
  int info_result = pcre2_pattern_info(
    validation, PCRE2_INFO_MINLENGTH, &minimum_length);
  pcre2_code_free(validation);
  if (info_result < 0) {
    luaL_error(L, "failed to inspect tokenizer regex");
  }
  if (!minimum_length) {
    luaL_error(L, "token regex must consume input");
  }
}


static size_t decimal_length(size_t value) {
  size_t length = 1;
  while (value >= 10) {
    value /= 10;
    length++;
  }
  return length;
}


static size_t write_decimal(char *destination, size_t value) {
  size_t length = decimal_length(value);
  for (size_t i = length; i > 0; i--) {
    destination[i - 1] = (char) ('0' + value % 10);
    value /= 10;
  }
  return length;
}


static void append_bytes(
  char *destination,
  size_t *offset,
  const char *source,
  size_t length
) {
  SDL_memcpy(destination + *offset, source, length);
  *offset += length;
}


static void compile_token_regex(lua_State *L, DocumentSyntax *syntax) {
  if (!syntax->pattern_count) { return; }

  static const char expression_open[] = "(?:";
  static const char branch_open[] = "(?:";
  static const char branch_mark[] = ")(*MARK:";

  size_t length = sizeof(expression_open);
  for (size_t i = 0; i < syntax->pattern_count; i++) {
    const SyntaxPattern *pattern = &syntax->patterns[i];
    size_t overhead = (i ? 1 : 0)
      + sizeof(branch_open) - 1
      + sizeof(branch_mark) - 1
      + decimal_length(i)
      + 1;
    if (overhead > SIZE_MAX - length
        || pattern->source_length > SIZE_MAX - length - overhead) {
      luaL_error(L, "tokenizer patterns are too large");
    }
    length += overhead + pattern->source_length;
  }

  char *combined = SDL_malloc(length + 1);
  if (!combined) { raise_out_of_memory(L); }
  size_t offset = 0;
  append_bytes(
    combined, &offset, expression_open, sizeof(expression_open) - 1);
  for (size_t i = 0; i < syntax->pattern_count; i++) {
    SyntaxPattern *pattern = &syntax->patterns[i];
    if (i) { combined[offset++] = '|'; }
    append_bytes(combined, &offset, branch_open, sizeof(branch_open) - 1);
    append_bytes(
      combined, &offset, pattern->source, pattern->source_length);
    append_bytes(combined, &offset, branch_mark, sizeof(branch_mark) - 1);
    offset += write_decimal(combined + offset, i);
    combined[offset++] = ')';
    SDL_free(pattern->source);
    pattern->source = NULL;
    pattern->source_length = 0;
  }
  combined[offset++] = ')';
  combined[offset] = '\0';
  SDL_assert(offset == length);
  syntax->token_regex = compile_owned_regex(L, combined, offset);
}


static void compile_patterns(lua_State *L, DocumentSyntax *syntax, int index) {
  lua_getfield(L, index, "patterns");
  luaL_checktype(L, -1, LUA_TTABLE);
  syntax->pattern_count = lua_rawlen(L, -1);
  if (syntax->pattern_count > SIZE_MAX / sizeof(*syntax->patterns)) {
    luaL_error(L, "too many tokenizer patterns");
  }
  if (syntax->pattern_count == 0) {
    lua_pop(L, 1);
    return;
  }
  syntax->patterns = SDL_calloc(syntax->pattern_count, sizeof(*syntax->patterns));
  if (!syntax->patterns) { raise_out_of_memory(L); }

  for (size_t i = 0; i < syntax->pattern_count; i++) {
    lua_geti(L, -1, (lua_Integer) i + 1);
    luaL_checktype(L, -1, LUA_TTABLE);
    compile_pattern(L, &syntax->patterns[i], lua_gettop(L));
    lua_pop(L, 1);
  }
  compile_token_regex(L, syntax);
  lua_pop(L, 1);
}


static uint64_t symbol_hash(const char *text, size_t length) {
  uint64_t hash = UINT64_C(14695981039346656037);
  for (size_t i = 0; i < length; i++) {
    hash ^= (unsigned char) text[i];
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}


static int compare_symbols(const void *left, const void *right) {
  const SyntaxSymbol *a = left;
  const SyntaxSymbol *b = right;
  return (a->hash > b->hash) - (a->hash < b->hash);
}


static void reserve_symbol(
  lua_State *L, DocumentSyntax *syntax, size_t *capacity
) {
  if (syntax->symbol_count < *capacity) { return; }

  size_t maximum = SIZE_MAX / sizeof(*syntax->symbols);
  if (*capacity == maximum) { raise_out_of_memory(L); }
  size_t next = *capacity ? *capacity * 2 : 16;
  if (next < *capacity || next > maximum) { next = maximum; }

  SyntaxSymbol *symbols = SDL_realloc(
    syntax->symbols, next * sizeof(*syntax->symbols));
  if (!symbols) { raise_out_of_memory(L); }
  syntax->symbols = symbols;
  *capacity = next;
}


static void compile_symbols(lua_State *L, DocumentSyntax *syntax, int index) {
  lua_getfield(L, index, "symbols");
  luaL_checktype(L, -1, LUA_TTABLE);

  size_t capacity = 0;
  lua_pushnil(L);
  while (lua_next(L, -2)) {
    luaL_checktype(L, -2, LUA_TSTRING);
    luaL_checktype(L, -1, LUA_TSTRING);
    reserve_symbol(L, syntax, &capacity);
    SyntaxSymbol *symbol = &syntax->symbols[syntax->symbol_count++];
    *symbol = (SyntaxSymbol) { 0 };
    lua_pushvalue(L, -2);
    symbol->text = duplicate_lua_string(L, -1, &symbol->length);
    symbol->hash = symbol_hash(symbol->text, symbol->length);
    lua_pop(L, 1);
    size_t type_length = 0;
    symbol->type = duplicate_lua_string(L, -1, &type_length);
    (void) type_length;
    lua_pop(L, 1);
  }
  if (syntax->symbol_count > 1) {
    qsort(
      syntax->symbols,
      syntax->symbol_count,
      sizeof(*syntax->symbols),
      compare_symbols);
  }
  lua_pop(L, 1);
}


int document_syntax_compile(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  DocumentSyntax *syntax = lua_newuserdatauv(L, sizeof(*syntax), 0);
  *syntax = (DocumentSyntax) { 0 };
  luaL_setmetatable(L, API_TYPE_DOCUMENT_SYNTAX);

  compile_patterns(L, syntax, 1);
  compile_symbols(L, syntax, 1);
  syntax->match_data = pcre2_match_data_create(1, NULL);
  if (!syntax->match_data) {
    return luaL_error(L, "out of memory while compiling syntax");
  }
  return 1;
}


static bool token_line_reserve(DocumentTokenLine *line, size_t capacity) {
  if (capacity <= line->token_capacity) { return true; }
  if (capacity > SIZE_MAX / sizeof(*line->tokens)) { return false; }
  size_t next = line->token_capacity ? line->token_capacity : 16;
  while (next < capacity) {
    if (next > SIZE_MAX / 2) {
      next = capacity;
      break;
    }
    next *= 2;
  }
  DocumentToken *tokens = SDL_realloc(line->tokens, next * sizeof(*tokens));
  if (!tokens) { return false; }
  line->tokens = tokens;
  line->token_capacity = next;
  return true;
}


static bool token_is_whitespace(const char *text, size_t length) {
  for (size_t i = 0; i < length; i++) {
    switch (text[i]) {
      case ' ': case '\f': case '\n': case '\r': case '\t': case '\v':
        break;
      default:
        return false;
    }
  }
  return true;
}


static bool token_line_push(
  DocumentTokenLine *line,
  const char *text,
  const char *type,
  size_t offset,
  size_t length
) {
  if (!length) { return true; }
  if (line->token_count) {
    DocumentToken *previous = &line->tokens[line->token_count - 1];
    if (!strcmp(previous->type, type)
        || token_is_whitespace(
          text + previous->offset, previous->length)) {
      previous->type = type;
      previous->length += length;
      return true;
    }
  }
  if (!token_line_reserve(line, line->token_count + 1)) { return false; }
  line->tokens[line->token_count++] = (DocumentToken) { type, offset, length };
  return true;
}


static const char *syntax_token_type(
  const DocumentSyntax *syntax,
  const SyntaxPattern *pattern,
  const char *text,
  size_t offset,
  size_t length
) {
  uint64_t hash = symbol_hash(text + offset, length);
  size_t first = 0;
  size_t last = syntax->symbol_count;
  while (first < last) {
    size_t middle = first + (last - first) / 2;
    if (syntax->symbols[middle].hash < hash) {
      first = middle + 1;
    } else {
      last = middle;
    }
  }
  for (size_t i = first;
       i < syntax->symbol_count && syntax->symbols[i].hash == hash;
       i++) {
    const SyntaxSymbol *symbol = &syntax->symbols[i];
    if (symbol->length == length
        && !SDL_memcmp(symbol->text, text + offset, length)) {
      return symbol->type;
    }
  }
  return pattern->type;
}


static bool match_regex(
  DocumentSyntax *syntax,
  pcre2_code *regex,
  const char *text,
  size_t text_length,
  size_t offset,
  uint32_t options,
  size_t *start,
  size_t *end,
  int *error_code
);


static bool find_next_token(
  DocumentSyntax *syntax,
  const char *text,
  size_t text_length,
  size_t offset,
  size_t *start,
  size_t *end,
  size_t *pattern_index,
  int *error_code
) {
  if (!syntax->token_regex) { return false; }
  if (!match_regex(
        syntax, syntax->token_regex, text, text_length, offset, 0,
        start, end, error_code)) {
    return false;
  }

  PCRE2_SPTR mark = pcre2_get_mark(syntax->match_data);
  if (!mark) {
    *error_code = PCRE2_ERROR_INTERNAL;
    return false;
  }
  size_t index = 0;
  for (const PCRE2_UCHAR *digit = mark; *digit; digit++) {
    if (*digit < '0' || *digit > '9'
        || index > (SIZE_MAX - (size_t) (*digit - '0')) / 10) {
      *error_code = PCRE2_ERROR_INTERNAL;
      return false;
    }
    index = index * 10 + (size_t) (*digit - '0');
  }
  if (index >= syntax->pattern_count) {
    *error_code = PCRE2_ERROR_INTERNAL;
    return false;
  }
  *pattern_index = index;
  return true;
}


static bool match_regex(
  DocumentSyntax *syntax,
  pcre2_code *regex,
  const char *text,
  size_t text_length,
  size_t offset,
  uint32_t options,
  size_t *start,
  size_t *end,
  int *error_code
) {
  int result = pcre2_match(
    regex,
    (PCRE2_SPTR) text,
    (PCRE2_SIZE) text_length,
    (PCRE2_SIZE) offset,
    options,
    syntax->match_data,
    NULL);
  if (result == PCRE2_ERROR_NOMATCH) { return false; }
  if (result < 0) {
    *error_code = result;
    return false;
  }
  PCRE2_SIZE *matches = pcre2_get_ovector_pointer(syntax->match_data);
  *start = (size_t) matches[0];
  *end = (size_t) matches[1];
  return true;
}


static bool match_is_escaped(
  const char *text, size_t offset, unsigned char escape
) {
  if (!escape) { return false; }
  size_t count = 0;
  while (offset && (unsigned char) text[offset - 1] == escape) {
    count++;
    offset--;
  }
  return count % 2 != 0;
}


static bool find_pair_end(
  DocumentSyntax *syntax,
  const SyntaxPattern *pattern,
  const char *text,
  size_t text_length,
  size_t offset,
  size_t *end,
  int *error_code
) {
  while (offset <= text_length) {
    size_t start = 0;
    if (!match_regex(
          syntax, pattern->end_regex, text, text_length, offset, 0,
          &start, end, error_code)) {
      return false;
    }
    if (!match_is_escaped(text, start, pattern->escape)) { return true; }
    offset = *end > offset ? *end : offset + 1;
  }
  return false;
}


bool document_syntax_tokenize_line(
  DocumentSyntax *syntax,
  const char *text,
  size_t text_length,
  size_t start_state,
  DocumentTokenLine *line,
  int *error_code
) {
  line->token_count = 0;
  line->end_state = start_state;
  *error_code = 0;
  size_t offset = 0;

  if (!syntax->pattern_count) {
    return token_line_push(line, text, "normal", 0, text_length);
  }

  while (offset < text_length) {
    if (line->end_state) {
      const SyntaxPattern *pattern = &syntax->patterns[line->end_state - 1];
      size_t end = 0;
      if (find_pair_end(
            syntax, pattern, text, text_length, offset, &end, error_code)) {
        if (!token_line_push(line, text, pattern->type, offset, end - offset)) {
          return false;
        }
        line->end_state = 0;
        offset = end;
      } else {
        if (*error_code) { return false; }
        bool success = token_line_push(
          line, text, pattern->type, offset, text_length - offset);
        return success;
      }
    }

    size_t start = 0;
    size_t end = 0;
    size_t pattern_index = 0;
    bool matched = find_next_token(
      syntax,
      text,
      text_length,
      offset,
      &start,
      &end,
      &pattern_index,
      error_code);
    if (*error_code) { return false; }
    if (matched) {
      if (!token_line_push(line, text, "normal", offset, start - offset)) {
        return false;
      }
      const SyntaxPattern *pattern = &syntax->patterns[pattern_index];
      const char *type = syntax_token_type(
        syntax, pattern, text, start, end - start);
      if (!token_line_push(line, text, type, start, end - start)) {
        return false;
      }
      if (pattern->end_regex) { line->end_state = pattern_index + 1; }
      offset = end;
    }

    if (!matched) {
      return token_line_push(
        line, text, "normal", offset, text_length - offset);
    }
  }
  return true;
}


void document_token_line_destroy(DocumentTokenLine *line) {
  SDL_free(line->tokens);
  *line = (DocumentTokenLine) { 0 };
}


const char *document_syntax_error_message(
  int error_code, char *buffer, size_t buffer_size
) {
  return regex_error_message(error_code, buffer, buffer_size);
}


static int f_syntax_gc(lua_State *L) {
  DocumentSyntax *syntax = document_syntax_check(L, 1);
  syntax_destroy(syntax);
  return 0;
}


void document_syntax_register(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_DOCUMENT_SYNTAX);
  lua_pushcfunction(L, f_syntax_gc);
  lua_setfield(L, -2, "__gc");
  lua_pop(L, 1);
}
