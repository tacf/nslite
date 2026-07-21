#include <SDL3/SDL.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "api.h"


/* Documents always contain at least one line. Every live line includes its
 * trailing '\n' and is NULL-terminated; byte_count excludes only that NULL.
 * Lines and columns are one-based (cause lua, maybe we can change this later on), 
 * and range end positions are exclusive. */
typedef struct {
  char *data;
  size_t byte_count;
} DocumentLine;


typedef struct {
  DocumentLine *lines;
  size_t line_count;
  size_t line_capacity;
  char *filename;
  uint64_t revision;
  bool crlf;
} Document;


typedef struct {
  size_t line;
  size_t column;
} DocumentPosition;


static Document *check_document(lua_State *L, int index) {
  return luaL_checkudata(L, index, API_TYPE_DOCUMENT);
}


// Document storage operations

static void line_destroy(DocumentLine *line) {
  SDL_free(line->data);
  *line = (DocumentLine) { 0 };
}


static void document_destroy(Document *document) {
  for (size_t i = 0; i < document->line_count; i++) {
    line_destroy(&document->lines[i]);
  }
  SDL_free(document->lines);
  SDL_free(document->filename);
  *document = (Document) { 0 };
}


static bool document_reserve_lines(Document *document, size_t capacity) {
  if (capacity <= document->line_capacity) { return true; }
  if (capacity > SIZE_MAX / sizeof(*document->lines)) { return false; }

  size_t next = document->line_capacity ? document->line_capacity : 8;
  while (next < capacity) {
    if (next > SIZE_MAX / 2) {
      next = capacity;
      break;
    }
    next *= 2;
  }

  DocumentLine *lines = SDL_realloc(document->lines, next * sizeof(*lines));
  if (!lines) { return false; }
  document->lines = lines;
  document->line_capacity = next;
  return true;
}


static bool document_append_line(
  Document *document, const char *data, size_t byte_count
) {
  if (byte_count > SIZE_MAX - 2) { return false; }
  if (!document_reserve_lines(document, document->line_count + 1)) {
    return false;
  }

  DocumentLine line = { 0 };
  line.data = SDL_malloc(byte_count + 2);
  if (!line.data) { return false; }
  if (byte_count) { SDL_memcpy(line.data, data, byte_count); }
  line.data[byte_count] = '\n';
  line.data[byte_count + 1] = '\0';
  line.byte_count = byte_count + 1;
  document->lines[document->line_count++] = line;
  return true;
}


static void document_replace(Document *document, Document *replacement) {
  replacement->revision = document->revision + 1;
  document_destroy(document);
  *document = *replacement;
  *replacement = (Document) { 0 };
}


static bool document_reset(Document *document) {
  Document replacement = { 0 };
  if (!document_append_line(&replacement, "", 0)) { return false; }
  document_replace(document, &replacement);
  return true;
}


// File IO Operations

static bool document_append_file_line(
  Document *document, const char *data, size_t byte_count
) {
  if (byte_count && data[byte_count - 1] == '\r') {
    byte_count--;
    document->crlf = true;
  }
  return document_append_line(document, data, byte_count);
}


static bool document_load(Document *document, const char *filename) {
  size_t file_size = 0;
  char *contents = SDL_LoadFile(filename, &file_size);
  if (!contents) { return false; }

  Document loaded = { 0 };
  loaded.filename = SDL_strdup(filename);
  bool success = loaded.filename != NULL;

  size_t line_start = 0;
  for (size_t i = 0; i < file_size && success; i++) {
    if (contents[i] != '\n') { continue; }
    success = document_append_file_line(
      &loaded, contents + line_start, i - line_start);
    line_start = i + 1;
  }

  if (success && line_start < file_size) {
    success = document_append_file_line(
      &loaded, contents + line_start, file_size - line_start);
  }
  if (success && loaded.line_count == 0) {
    success = document_append_line(&loaded, "", 0);
  }

  SDL_free(contents);
  if (!success) {
    document_destroy(&loaded);
    SDL_SetError("Out of memory while loading document");
    return false;
  }
  document_replace(document, &loaded);
  return true;
}


static bool io_write_all(
  SDL_IOStream *stream, const char *data, size_t byte_count
) {
  while (byte_count) {
    size_t written = SDL_WriteIO(stream, data, byte_count);
    if (!written) { return false; }
    data += written;
    byte_count -= written;
  }
  return true;
}


static bool document_save(Document *document, const char *filename, bool crlf) {
  char *stored_filename = SDL_strdup(filename);
  if (!stored_filename) { return false; }
  SDL_IOStream *stream = SDL_IOFromFile(filename, "wb");
  if (!stream) {
    SDL_free(stored_filename);
    return false;
  }

  bool success = true;
  for (size_t i = 0; i < document->line_count && success; i++) {
    const DocumentLine *line = &document->lines[i];
    if (crlf) {
      success = io_write_all(stream, line->data, line->byte_count - 1)
        && io_write_all(stream, "\r\n", 2);
    } else {
      success = io_write_all(stream, line->data, line->byte_count);
    }
  }

  if (!success) {
    char error[256];
    SDL_strlcpy(error, SDL_GetError(), sizeof(error));
    SDL_CloseIO(stream);
    SDL_free(stored_filename);
    SDL_SetError("Failed to write document: %s", error);
    return false;
  }
  if (!SDL_CloseIO(stream)) {
    SDL_free(stored_filename);
    return false;
  }
  SDL_free(document->filename);
  document->filename = stored_filename;
  document->crlf = crlf;
  return true;
}


// Editing and text references operations

static size_t lua_check_clamped_index(
  lua_State *L, int index, size_t maximum
) {
  lua_Number value = luaL_checknumber(L, index);
  if (isnan(value) || value <= 1) { return 1; }
  if (value >= (lua_Number) maximum) { return maximum; }
  return (size_t) luaL_checkinteger(L, index);
}


static DocumentPosition lua_check_position(
  lua_State *L, const Document *document, int line_index, int column_index
) {
  size_t line = lua_check_clamped_index(L, line_index, document->line_count);
  size_t column = lua_check_clamped_index(
    L, column_index, document->lines[line - 1].byte_count);
  return (DocumentPosition) { line, column };
}


static void position_sort(DocumentPosition *a, DocumentPosition *b) {
  if (a->line < b->line || (a->line == b->line && a->column <= b->column)) {
    return;
  }
  DocumentPosition temporary = *a;
  *a = *b;
  *b = temporary;
}


static bool line_join(
  DocumentLine *result,
  const char *first, size_t first_length,
  const char *second, size_t second_length,
  const char *third, size_t third_length
) {
  if (first_length > SIZE_MAX - second_length
      || first_length + second_length > SIZE_MAX - third_length) {
    return false;
  }
  size_t length = first_length + second_length + third_length;
  if (length == SIZE_MAX) { return false; }

  char *data = SDL_malloc(length + 1);
  if (!data) { return false; }
  size_t offset = 0;
  if (first_length) {
    SDL_memcpy(data + offset, first, first_length);
    offset += first_length;
  }
  if (second_length) {
    SDL_memcpy(data + offset, second, second_length);
    offset += second_length;
  }
  if (third_length) { SDL_memcpy(data + offset, third, third_length); }
  data[length] = '\0';
  result->data = data;
  result->byte_count = length;
  return true;
}


static bool document_insert(
  Document *document, DocumentPosition at, const char *text, size_t text_length,
  DocumentPosition *end_position
) {
  size_t new_line_count = 1;
  for (size_t i = 0; i < text_length; i++) {
    if (text[i] == '\n') { new_line_count++; }
  }
  if (new_line_count - 1 > SIZE_MAX - document->line_count) { return false; }

  DocumentLine *new_lines = SDL_calloc(new_line_count, sizeof(*new_lines));
  if (!new_lines) { return false; }

  DocumentLine *original = &document->lines[at.line - 1];
  size_t prefix_length = at.column - 1;
  const char *suffix = original->data + prefix_length;
  size_t suffix_length = original->byte_count - prefix_length;
  size_t segment_start = 0;
  size_t new_line_index = 0;
  bool success = true;

  for (size_t i = 0; i <= text_length && success; i++) {
    if (i < text_length && text[i] != '\n') { continue; }
    bool last = i == text_length;
    const char *prefix = new_line_index == 0 ? original->data : NULL;
    size_t current_prefix_length = new_line_index == 0 ? prefix_length : 0;
    const char *current_suffix = last ? suffix : "\n";
    size_t current_suffix_length = last ? suffix_length : 1;
    success = line_join(
      &new_lines[new_line_index],
      prefix, current_prefix_length,
      text + segment_start, i - segment_start,
      current_suffix, current_suffix_length);
    new_line_index++;
    segment_start = i + 1;
  }

  size_t resulting_line_count = document->line_count + new_line_count - 1;
  if (success) {
    success = document_reserve_lines(document, resulting_line_count);
  }
  if (!success) {
    for (size_t i = 0; i < new_line_count; i++) {
      line_destroy(&new_lines[i]);
    }
    SDL_free(new_lines);
    return false;
  }

  size_t index = at.line - 1;
  size_t tail_count = document->line_count - index - 1;
  line_destroy(original);
  SDL_memmove(
    document->lines + index + new_line_count,
    document->lines + index + 1,
    tail_count * sizeof(*document->lines));
  SDL_memcpy(
    document->lines + index,
    new_lines,
    new_line_count * sizeof(*document->lines));
  SDL_free(new_lines);
  document->line_count = resulting_line_count;
  document->revision++;

  end_position->line = at.line + new_line_count - 1;
  if (new_line_count == 1) {
    end_position->column = at.column + text_length;
  } else {
    size_t last_newline = text_length;
    while (last_newline > 0 && text[last_newline - 1] != '\n') { last_newline--; }
    end_position->column = text_length - last_newline + 1;
  }
  return true;
}


static bool document_remove(
  Document *document, DocumentPosition start, DocumentPosition end
) {
  const DocumentLine *first = &document->lines[start.line - 1];
  const DocumentLine *last = &document->lines[end.line - 1];
  size_t prefix_length = start.column - 1;
  size_t suffix_offset = end.column - 1;
  DocumentLine replacement = { 0 };
  if (!line_join(
        &replacement,
        first->data, prefix_length,
        NULL, 0,
        last->data + suffix_offset, last->byte_count - suffix_offset)) {
    return false;
  }

  size_t first_index = start.line - 1;
  size_t last_index = end.line - 1;
  size_t removed_count = last_index - first_index + 1;
  for (size_t i = first_index; i <= last_index; i++) {
    line_destroy(&document->lines[i]);
  }
  document->lines[first_index] = replacement;

  size_t tail_count = document->line_count - last_index - 1;
  SDL_memmove(
    document->lines + first_index + 1,
    document->lines + last_index + 1,
    tail_count * sizeof(*document->lines));
  document->line_count -= removed_count - 1;
  document->revision++;
  return true;
}


static DocumentPosition document_position_offset(
  const Document *document, DocumentPosition position, lua_Integer offset
) {
  size_t line = position.line - 1;
  size_t column = position.column;

  if (offset < 0) {
    uint64_t remaining = (uint64_t) (-(offset + 1)) + 1;
    while (remaining) {
      size_t available = column - 1;
      if (remaining <= available) {
        column -= (size_t) remaining;
        break;
      }
      if (line == 0) {
        column = 1;
        break;
      }
      remaining -= (uint64_t) available + 1;
      line--;
      column = document->lines[line].byte_count;
    }
  } else {
    uint64_t remaining = (uint64_t) offset;
    while (remaining) {
      size_t available = document->lines[line].byte_count - column;
      if (remaining <= available) {
        column += (size_t) remaining;
        break;
      }
      if (line + 1 == document->line_count) {
        column = document->lines[line].byte_count;
        break;
      }
      remaining -= (uint64_t) available + 1;
      line++;
      column = 1;
    }
  }

  return (DocumentPosition) { line + 1, column };
}


// Bidings definition

static int lua_push_position(lua_State *L, DocumentPosition position) {
  lua_pushinteger(L, (lua_Integer) position.line);
  lua_pushinteger(L, (lua_Integer) position.column);
  return 2;
}


static int lua_push_sdl_result(
  lua_State *L, bool success, const char *operation
) {
  if (success) {
    lua_pushboolean(L, true);
    return 1;
  }
  lua_pushnil(L);
  lua_pushfstring(
    L, "failed to %s document: %s", operation, SDL_GetError());
  return 2;
}


static int f_new(lua_State *L) {
  Document *document = lua_newuserdatauv(L, sizeof(*document), 0);
  *document = (Document) { 0 };
  if (!document_reset(document)) {
    return luaL_error(L, "out of memory while creating document");
  }
  luaL_setmetatable(L, API_TYPE_DOCUMENT);
  return 1;
}


static int f_reset(lua_State *L) {
  Document *document = check_document(L, 1);
  if (!document_reset(document)) {
    return luaL_error(L, "out of memory while resetting document");
  }
  return 0;
}


static int f_load(lua_State *L) {
  Document *document = check_document(L, 1);
  const char *filename = luaL_checkstring(L, 2);
  return lua_push_sdl_result(
    L, document_load(document, filename), "load");
}


static int f_save(lua_State *L) {
  Document *document = check_document(L, 1);
  const char *filename = luaL_optstring(L, 2, document->filename);
  if (!filename) {
    lua_pushnil(L);
    lua_pushliteral(L, "document has no filename");
    return 2;
  }
  bool crlf = lua_isnoneornil(L, 3) ? document->crlf : lua_toboolean(L, 3);
  return lua_push_sdl_result(
    L, document_save(document, filename, crlf), "save");
}


static int f_line_count(lua_State *L) {
  Document *document = check_document(L, 1);
  lua_pushinteger(L, (lua_Integer) document->line_count);
  return 1;
}


static int f_get_line(lua_State *L) {
  Document *document = check_document(L, 1);
  lua_Integer line = luaL_checkinteger(L, 2);
  if (line < 1 || (uint64_t) line > document->line_count) { return 0; }
  const DocumentLine *result = &document->lines[line - 1];
  lua_pushlstring(L, result->data, result->byte_count);
  return 1;
}


static int f_sanitize_position(lua_State *L) {
  Document *document = check_document(L, 1);
  return lua_push_position(L, lua_check_position(L, document, 2, 3));
}


static int f_position_offset(lua_State *L) {
  Document *document = check_document(L, 1);
  DocumentPosition position = lua_check_position(L, document, 2, 3);
  lua_Integer offset = luaL_checkinteger(L, 4);
  return lua_push_position(
    L, document_position_offset(document, position, offset));
}


static int f_get_text(lua_State *L) {
  Document *document = check_document(L, 1);
  DocumentPosition start = lua_check_position(L, document, 2, 3);
  DocumentPosition end = lua_check_position(L, document, 4, 5);
  position_sort(&start, &end);

  if (start.line == end.line) {
    const DocumentLine *line = &document->lines[start.line - 1];
    lua_pushlstring(
      L, line->data + start.column - 1, end.column - start.column);
    return 1;
  }

  luaL_Buffer buffer;
  luaL_buffinit(L, &buffer);
  const DocumentLine *first = &document->lines[start.line - 1];
  luaL_addlstring(
    &buffer,
    first->data + start.column - 1,
    first->byte_count - start.column + 1);
  for (size_t line = start.line + 1; line < end.line; line++) {
    const DocumentLine *current = &document->lines[line - 1];
    luaL_addlstring(&buffer, current->data, current->byte_count);
  }
  const DocumentLine *last = &document->lines[end.line - 1];
  luaL_addlstring(&buffer, last->data, end.column - 1);
  luaL_pushresult(&buffer);
  return 1;
}


static int f_get_char(lua_State *L) {
  Document *document = check_document(L, 1);
  DocumentPosition position = lua_check_position(L, document, 2, 3);
  const DocumentLine *line = &document->lines[position.line - 1];
  lua_pushlstring(L, line->data + position.column - 1, 1);
  return 1;
}


static int f_insert(lua_State *L) {
  Document *document = check_document(L, 1);
  DocumentPosition position = lua_check_position(L, document, 2, 3);
  size_t text_length = 0;
  const char *text = luaL_checklstring(L, 4, &text_length);
  DocumentPosition end;
  if (!document_insert(document, position, text, text_length, &end)) {
    return luaL_error(L, "out of memory while inserting document text");
  }
  return lua_push_position(L, end);
}


static int f_remove(lua_State *L) {
  Document *document = check_document(L, 1);
  DocumentPosition start = lua_check_position(L, document, 2, 3);
  DocumentPosition end = lua_check_position(L, document, 4, 5);
  position_sort(&start, &end);
  if (!document_remove(document, start, end)) {
    return luaL_error(L, "out of memory while removing document text");
  }
  return 0;
}


static int f_revision(lua_State *L) {
  Document *document = check_document(L, 1);
  lua_pushinteger(L, (lua_Integer) document->revision);
  return 1;
}


static int f_filename(lua_State *L) {
  Document *document = check_document(L, 1);
  if (!document->filename) { return 0; }
  lua_pushstring(L, document->filename);
  return 1;
}


static int f_is_crlf(lua_State *L) {
  Document *document = check_document(L, 1);
  lua_pushboolean(L, document->crlf);
  return 1;
}


static int f_set_crlf(lua_State *L) {
  Document *document = check_document(L, 1);
  luaL_checktype(L, 2, LUA_TBOOLEAN);
  document->crlf = lua_toboolean(L, 2);
  return 0;
}


static int f_gc(lua_State *L) {
  Document *document = check_document(L, 1);
  document_destroy(document);
  return 0;
}


static const luaL_Reg document_lib[] = {
  { "__gc",              f_gc                },
  { "reset",             f_reset             },
  { "load",              f_load              },
  { "save",              f_save              },
  { "line_count",        f_line_count        },
  { "get_line",          f_get_line          },
  { "sanitize_position", f_sanitize_position },
  { "position_offset",   f_position_offset   },
  { "get_text",          f_get_text          },
  { "get_char",          f_get_char          },
  { "insert",            f_insert            },
  { "remove",            f_remove            },
  { "revision",          f_revision          },
  { "filename",          f_filename          },
  { "is_crlf",           f_is_crlf           },
  { "set_crlf",          f_set_crlf          },
  { NULL, NULL }
};


static const luaL_Reg module_lib[] = {
  { "new", f_new },
  { NULL, NULL }
};


int luaopen_document(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_DOCUMENT);
  luaL_setfuncs(L, document_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  luaL_newlib(L, module_lib);
  return 1;
}
