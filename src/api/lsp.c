#include <SDL3/SDL.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "api.h"
#include "cJSON.h"
#include "document.h"
#include "utils/path.h"
#include "utils/utf8.h"


// Guard against malformed servers growing transport buffers without bound.
#define LSP_MAX_HEADER_SIZE (64 * 1024)
#define LSP_MAX_MESSAGE_SIZE (64 * 1024 * 1024)
#define LSP_MAX_BUFFER_SIZE (LSP_MAX_MESSAGE_SIZE + LSP_MAX_HEADER_SIZE)

// Bound pipe I/O work performed during one editor update.
#define LSP_READ_CHUNK_SIZE 8192
#define LSP_IO_BUDGET (256 * 1024)


typedef struct {
  char *data;
  size_t length;
  size_t capacity;
} Buffer;


typedef struct {
  const char *begin;
  const char *end;
} JsonSlice;


typedef struct OpenDocument OpenDocument;
struct OpenDocument {
  char *uri;
  uint64_t revision;
  uint32_t version;
  OpenDocument *next;
};


typedef enum {
  QUERY_NONE,
  QUERY_PENDING,
  QUERY_READY,
  QUERY_MISSING
} QueryState;


typedef struct {
  SDL_Process *process;
  SDL_IOStream *input;
  SDL_IOStream *output;
  SDL_IOStream *error;
  Buffer reads;
  Buffer writes;
  size_t write_offset;
  bool stdout_eof;
  bool stderr_eof;
  bool exited;
  bool initialized;
  int exit_code;
  char transport_error[256];
  char *root_uri;
  OpenDocument *documents;
  uint32_t next_request_id;
  uint32_t initialize_id;
  uint32_t definition_id;
  QueryState query_state;
  char *query_uri;
  uint64_t query_revision;
  size_t query_line;
  size_t query_start;
  size_t query_end;
  char *target_path;
  size_t target_line;
  size_t target_character;
} LspClient;


static LspClient *check_client(lua_State *L) {
  return luaL_checkudata(L, 1, API_TYPE_LSP_CLIENT);
}


static void set_transport_error(LspClient *client, const char *message) {
  if (client->transport_error[0]) { return; }
  SDL_strlcpy(
    client->transport_error, message, sizeof(client->transport_error));
}


static void set_sdl_error(LspClient *client, const char *operation) {
  const char *detail = SDL_GetError();
  if (!detail || !detail[0]) { detail = "unknown I/O error"; }
  SDL_snprintf(client->transport_error, sizeof(client->transport_error),
    "%s: %s", operation, detail);
}


static bool buffer_reserve(Buffer *buffer, size_t required) {
  if (required <= buffer->capacity) { return true; }
  if (required > LSP_MAX_BUFFER_SIZE) { return false; }

  size_t next = buffer->capacity ? buffer->capacity : LSP_READ_CHUNK_SIZE;
  while (next < required) {
    if (next > LSP_MAX_BUFFER_SIZE / 2) {
      next = LSP_MAX_BUFFER_SIZE;
      break;
    }
    next *= 2;
  }

  char *resized = SDL_realloc(buffer->data, next);
  if (!resized) { return false; }
  buffer->data = resized;
  buffer->capacity = next;
  return true;
}


static bool buffer_append(Buffer *buffer, const char *data, size_t length) {
  if (length > LSP_MAX_BUFFER_SIZE - buffer->length) { return false; }
  size_t required = buffer->length + length;
  if (!buffer_reserve(buffer, required)) { return false; }
  if (length) { SDL_memcpy(buffer->data + buffer->length, data, length); }
  buffer->length = required;
  return true;
}


static void buffer_clear(Buffer *buffer) {
  SDL_free(buffer->data);
  *buffer = (Buffer) { 0 };
}


static bool append_read_data(
  LspClient *client, const char *data, size_t length) {
  if (!buffer_append(&client->reads, data, length)) {
    set_transport_error(client, "incoming LSP data exceeds the 64 MiB limit");
    return false;
  }
  return true;
}


static bool append_write_data(
  LspClient *client, const char *data, size_t length) {
  if (client->write_offset) {
    size_t pending = client->writes.length - client->write_offset;
    SDL_memmove(
      client->writes.data, client->writes.data + client->write_offset, pending);
    client->write_offset = 0;
    client->writes.length = pending;
  }
  if (!buffer_append(&client->writes, data, length)) {
    set_transport_error(client, "outgoing LSP data exceeds the 64 MiB limit");
    return false;
  }
  return true;
}


static bool flush_writes(LspClient *client) {
  while (client->write_offset < client->writes.length) {
    size_t written =
      SDL_WriteIO(client->input, client->writes.data + client->write_offset,
        client->writes.length - client->write_offset);
    if (written) {
      client->write_offset += written;
      continue;
    }
    if (SDL_GetIOStatus(client->input) == SDL_IO_STATUS_NOT_READY) {
      return true;
    }
    set_sdl_error(client, "failed to write to language server");
    return false;
  }
  client->write_offset = 0;
  client->writes.length = 0;
  return true;
}


static bool send_body(LspClient *client, const Buffer *body) {
  if (body->length > LSP_MAX_MESSAGE_SIZE) {
    set_transport_error(client, "LSP message exceeds the 64 MiB limit");
    return false;
  }
  char header[64];
  int header_length = SDL_snprintf(
    header, sizeof(header), "Content-Length: %zu\r\n\r\n", body->length);
  if (header_length < 0 || (size_t) header_length >= sizeof(header)
    || !append_write_data(client, header, (size_t) header_length)
    || !append_write_data(client, body->data, body->length)) {
    return false;
  }
  return flush_writes(client);
}


static bool send_json(LspClient *client, const cJSON *json) {
  char *text = cJSON_PrintUnformatted(json);
  if (!text) {
    set_transport_error(client, "out of memory encoding LSP message");
    return false;
  }
  Buffer body = { text, SDL_strlen(text), 0 };
  bool success = send_body(client, &body);
  cJSON_free(text);
  return success;
}


static bool ascii_equal(const char *text, size_t length, const char *expected) {
  size_t expected_length = SDL_strlen(expected);
  if (length != expected_length) { return false; }
  for (size_t i = 0; i < length; i++) {
    unsigned char a = (unsigned char) text[i];
    unsigned char b = (unsigned char) expected[i];
    if (a >= 'A' && a <= 'Z') { a = (unsigned char) (a + ('a' - 'A')); }
    if (b >= 'A' && b <= 'Z') { b = (unsigned char) (b + ('a' - 'A')); }
    if (a != b) { return false; }
  }
  return true;
}


static const char *find_bytes(
  const char *data, size_t length, const char *needle, size_t needle_length) {
  if (needle_length > length) { return NULL; }
  for (size_t i = 0; i <= length - needle_length; i++) {
    if (SDL_memcmp(data + i, needle, needle_length) == 0) { return data + i; }
  }
  return NULL;
}


/* Returns 1 for a complete frame, 0 when incomplete, and -1 on error. */
static int frame_body(LspClient *client, JsonSlice *body, size_t *consumed) {
  const char *header_end =
    find_bytes(client->reads.data, client->reads.length, "\r\n\r\n", 4);
  if (!header_end) {
    if (client->reads.length > LSP_MAX_HEADER_SIZE) {
      set_transport_error(client, "LSP header exceeds the 64 KiB limit");
      return -1;
    }
    return 0;
  }

  size_t header_length = (size_t) (header_end - client->reads.data);
  size_t content_length = 0;
  bool found_content_length = false;
  const char *line = client->reads.data;
  const char *limit = client->reads.data + header_length;
  while (line < limit) {
    const char *line_end = find_bytes(line, (size_t) (limit - line), "\r\n", 2);
    if (!line_end) { line_end = limit; }
    const char *colon = find_bytes(line, (size_t) (line_end - line), ":", 1);
    if (!colon) {
      set_transport_error(client, "malformed LSP header");
      return -1;
    }
    const char *name_end = colon;
    while (name_end > line && (name_end[-1] == ' ' || name_end[-1] == '\t')) {
      name_end--;
    }
    if (ascii_equal(line, (size_t) (name_end - line), "Content-Length")) {
      if (found_content_length) {
        set_transport_error(client, "duplicate Content-Length in LSP header");
        return -1;
      }
      const char *value = colon + 1;
      while (value < line_end && (*value == ' ' || *value == '\t')) { value++; }
      if (value == line_end || *value < '0' || *value > '9') {
        set_transport_error(client, "invalid Content-Length in LSP header");
        return -1;
      }
      while (value < line_end && *value >= '0' && *value <= '9') {
        unsigned int digit = (unsigned int) (*value - '0');
        if (content_length > (LSP_MAX_MESSAGE_SIZE - digit) / 10) {
          set_transport_error(client, "LSP message exceeds the 64 MiB limit");
          return -1;
        }
        content_length = content_length * 10 + digit;
        value++;
      }
      while (value < line_end && (*value == ' ' || *value == '\t')) { value++; }
      if (value != line_end) {
        set_transport_error(client, "invalid Content-Length in LSP header");
        return -1;
      }
      found_content_length = true;
    }
    line = line_end + (line_end < limit ? 2 : 0);
  }

  if (!found_content_length) {
    set_transport_error(client, "LSP header is missing Content-Length");
    return -1;
  }
  size_t body_offset = header_length + 4;
  if (client->reads.length - body_offset < content_length) { return 0; }
  body->begin = client->reads.data + body_offset;
  body->end = body->begin + content_length;
  *consumed = body_offset + content_length;
  return 1;
}


static cJSON *parse_json_message(JsonSlice message) {
  const char *parse_end = NULL;
  cJSON *json = cJSON_ParseWithLengthOpts(
    message.begin, (size_t) (message.end - message.begin), &parse_end, false);
  if (!json) { return NULL; }
  while (parse_end < message.end
    && (*parse_end == ' ' || *parse_end == '\t' || *parse_end == '\r'
      || *parse_end == '\n')) {
    parse_end++;
  }
  if (parse_end != message.end) {
    cJSON_Delete(json);
    return NULL;
  }
  return json;
}


static bool json_u32(const cJSON *value, uint32_t *result) {
  if (!cJSON_IsNumber(value) || !(value->valuedouble >= 0.0)
    || value->valuedouble > (double) UINT32_MAX) {
    return false;
  }
  uint32_t number = (uint32_t) value->valuedouble;
  if ((double) number != value->valuedouble) { return false; }
  *result = number;
  return true;
}


static bool json_size(const cJSON *value, size_t *result) {
  if (!cJSON_IsNumber(value) || !(value->valuedouble >= 0.0)
    || value->valuedouble > (double) SIZE_MAX) {
    return false;
  }
  size_t number = (size_t) value->valuedouble;
  if ((double) number != value->valuedouble) { return false; }
  *result = number;
  return true;
}


static cJSON *create_message(const char *method, uint32_t id) {
  cJSON *message = cJSON_CreateObject();
  if (!message || !cJSON_AddStringToObject(message, "jsonrpc", "2.0")
    || (id && !cJSON_AddNumberToObject(message, "id", (double) id))
    || !cJSON_AddStringToObject(message, "method", method)) {
    cJSON_Delete(message);
    return NULL;
  }
  return message;
}


static bool parse_definition(LspClient *client, const cJSON *result) {
  if (!result || cJSON_IsNull(result)) { return false; }
  const cJSON *location = result;
  if (cJSON_IsArray(result)) { location = cJSON_GetArrayItem(result, 0); }
  if (!cJSON_IsObject(location)) { return false; }

  const cJSON *uri = cJSON_GetObjectItemCaseSensitive(location, "targetUri");
  if (!cJSON_IsString(uri)) {
    uri = cJSON_GetObjectItemCaseSensitive(location, "uri");
  }
  const cJSON *range =
    cJSON_GetObjectItemCaseSensitive(location, "targetSelectionRange");
  if (!cJSON_IsObject(range)) {
    range = cJSON_GetObjectItemCaseSensitive(location, "targetRange");
  }
  if (!cJSON_IsObject(range)) {
    range = cJSON_GetObjectItemCaseSensitive(location, "range");
  }
  if (!cJSON_IsString(uri) || !cJSON_IsObject(range)) { return false; }

  const cJSON *start = cJSON_GetObjectItemCaseSensitive(range, "start");
  const cJSON *line_value = cJSON_GetObjectItemCaseSensitive(start, "line");
  const cJSON *character_value =
    cJSON_GetObjectItemCaseSensitive(start, "character");
  size_t line;
  size_t character;
  char *path = file_uri_to_path(uri->valuestring);
  if (!path || !json_size(line_value, &line)
    || !json_size(character_value, &character)) {
    SDL_free(path);
    return false;
  }
  SDL_free(client->target_path);
  client->target_path = path;
  client->target_line = line;
  client->target_character = character;
  return true;
}


static bool send_initialized(LspClient *client) {
  cJSON *message = create_message("initialized", 0);
  bool success = message && cJSON_AddObjectToObject(message, "params");
  if (success) { success = send_json(client, message); }
  cJSON_Delete(message);
  if (!success && !client->transport_error[0]) {
    set_transport_error(
      client, "out of memory encoding initialized notification");
  }
  return success;
}


static void process_message(LspClient *client, JsonSlice body) {
  cJSON *message = parse_json_message(body);
  if (!message) {
    set_transport_error(client, "language server sent invalid JSON");
    return;
  }
  const cJSON *id_value = cJSON_GetObjectItemCaseSensitive(message, "id");
  uint32_t id;
  if (!json_u32(id_value, &id)) {
    cJSON_Delete(message);
    return;
  }
  const cJSON *error = cJSON_GetObjectItemCaseSensitive(message, "error");
  bool has_error = error && !cJSON_IsNull(error);
  if (id == client->initialize_id && !client->initialized) {
    if (has_error) {
      set_transport_error(client, "language server rejected initialization");
    } else if (!cJSON_GetObjectItemCaseSensitive(message, "result")) {
      set_transport_error(
        client, "language server returned an invalid initialize response");
    } else {
      client->initialized = true;
      if (!send_initialized(client)) {
        set_transport_error(client, "failed to send initialized notification");
      }
    }
  } else if (id == client->definition_id
    && client->query_state == QUERY_PENDING) {
    const cJSON *result = cJSON_GetObjectItemCaseSensitive(message, "result");
    client->query_state = !has_error && parse_definition(client, result)
      ? QUERY_READY
      : QUERY_MISSING;
  }
  cJSON_Delete(message);
}


static void update_status(LspClient *client) {
  if (!client->process || client->exited) { return; }
  int exit_code = 0;
  if (SDL_WaitProcess(client->process, false, &exit_code)) {
    client->exited = true;
    client->exit_code = exit_code;
  }
}


static bool process_frames(LspClient *client) {
  while (true) {
    JsonSlice body;
    size_t consumed = 0;
    int framed = frame_body(client, &body, &consumed);
    if (framed < 0) { return false; }
    if (framed == 0) { return true; }
    process_message(client, body);
    size_t remaining = client->reads.length - consumed;
    SDL_memmove(client->reads.data, client->reads.data + consumed, remaining);
    client->reads.length = remaining;
    if (client->transport_error[0]) { return false; }
  }
}


static bool pump_client(LspClient *client) {
  if (client->transport_error[0]) { return false; }
  if (!flush_writes(client) || !process_frames(client)) { return false; }

  char chunk[LSP_READ_CHUNK_SIZE];
  size_t read_total = 0;
  while (!client->stdout_eof && read_total < LSP_IO_BUDGET) {
    size_t received = SDL_ReadIO(client->output, chunk, sizeof(chunk));
    if (received) {
      read_total += received;
      if (!append_read_data(client, chunk, received)
        || !process_frames(client)) {
        return false;
      }
      continue;
    }
    SDL_IOStatus status = SDL_GetIOStatus(client->output);
    if (status == SDL_IO_STATUS_NOT_READY) { break; }
    if (status == SDL_IO_STATUS_EOF) {
      client->stdout_eof = true;
      break;
    }
    set_sdl_error(client, "failed to read from language server");
    return false;
  }

  size_t error_total = 0;
  while (!client->stderr_eof && error_total < LSP_IO_BUDGET) {
    size_t received = SDL_ReadIO(client->error, chunk, sizeof(chunk));
    if (received) {
      error_total += received;
      continue;
    }
    SDL_IOStatus status = SDL_GetIOStatus(client->error);
    if (status == SDL_IO_STATUS_NOT_READY) { break; }
    if (status == SDL_IO_STATUS_EOF) {
      client->stderr_eof = true;
      break;
    }
    set_sdl_error(client, "failed to read language server stderr");
    return false;
  }

  if (client->stdout_eof && client->reads.length) {
    set_transport_error(
      client, "language server closed stdout during an LSP message");
    return false;
  }
  update_status(client);
  if (client->exited) {
    char message[128];
    SDL_snprintf(message, sizeof(message),
      "language server exited with code %d", client->exit_code);
    set_transport_error(client, message);
    return false;
  }
  return true;
}


static bool document_text(
  LspClient *client, const Document *document, Buffer *text) {
  size_t count = document_line_count(document);
  for (size_t i = 0; i < count; i++) {
    size_t length;
    const char *line = document_line(document, i, &length);
    if (!line || memchr(line, '\0', length)) {
      set_transport_error(client, "LSP documents cannot contain zero bytes");
      return false;
    }
    if (!buffer_append(text, line, length)) {
      set_transport_error(client, "document exceeds the 64 MiB LSP limit");
      return false;
    }
  }
  if (!buffer_append(text, "", 1)) {
    set_transport_error(client, "document exceeds the 64 MiB LSP limit");
    return false;
  }
  return true;
}


static bool add_string_reference(
  cJSON *object, const char *name, const char *value) {
  cJSON *string = cJSON_CreateStringReference(value);
  if (!string) { return false; }
  if (!cJSON_AddItemToObject(object, name, string)) {
    cJSON_Delete(string);
    return false;
  }
  return true;
}


static OpenDocument *find_open_document(LspClient *client, const char *uri) {
  for (OpenDocument *open = client->documents; open; open = open->next) {
    if (SDL_strcmp(open->uri, uri) == 0) { return open; }
  }
  return NULL;
}


static bool sync_document(LspClient *client, const Document *document,
  const char *language_id, const char *uri) {
  uint64_t revision = document_revision(document);
  OpenDocument *open = find_open_document(client, uri);
  if (open && open->revision == revision) { return true; }
  if (open && open->version == UINT32_MAX) {
    set_transport_error(client, "LSP document version limit reached");
    return false;
  }

  Buffer text = { 0 };
  if (!document_text(client, document, &text)) {
    buffer_clear(&text);
    return false;
  }

  cJSON *message =
    create_message(open ? "textDocument/didChange" : "textDocument/didOpen", 0);
  cJSON *params = message ? cJSON_AddObjectToObject(message, "params") : NULL;
  cJSON *text_document =
    params ? cJSON_AddObjectToObject(params, "textDocument") : NULL;
  bool success =
    text_document && cJSON_AddStringToObject(text_document, "uri", uri);

  if (!open) {
    success = success
      && cJSON_AddStringToObject(text_document, "languageId", language_id)
      && cJSON_AddNumberToObject(text_document, "version", 1.0)
      && add_string_reference(text_document, "text", text.data);
  } else {
    cJSON *changes =
      success ? cJSON_AddArrayToObject(params, "contentChanges") : NULL;
    cJSON *change = changes ? cJSON_CreateObject() : NULL;
    if (!change || !cJSON_AddItemToArray(changes, change)) {
      cJSON_Delete(change);
      success = false;
    } else {
      success = cJSON_AddNumberToObject(
                  text_document, "version", (double) open->version + 1.0)
        && add_string_reference(change, "text", text.data);
    }
  }

  if (success) { success = send_json(client, message); }
  cJSON_Delete(message);
  buffer_clear(&text);
  if (!success) {
    if (!client->transport_error[0]) {
      set_transport_error(client, "out of memory encoding document update");
    }
    return false;
  }

  if (!open) {
    open = SDL_calloc(1, sizeof(*open));
    if (!open) {
      set_transport_error(client, "out of memory tracking LSP document");
      return false;
    }
    open->uri = SDL_strdup(uri);
    if (!open->uri) {
      SDL_free(open);
      set_transport_error(client, "out of memory tracking LSP document");
      return false;
    }
    open->version = 1;
    open->next = client->documents;
    client->documents = open;
  } else {
    open->version++;
  }
  open->revision = revision;
  return true;
}


static bool word_byte(unsigned char byte) {
  return byte >= 0x80 || byte == '_' || byte == '$' || isalnum(byte);
}


static bool document_word(const Document *document, size_t line, size_t column,
  size_t *start, size_t *end, size_t *character) {
  size_t length;
  const char *text = document_line(document, line, &length);
  if (!text || column >= length || text[column] == '\n'
    || !word_byte((unsigned char) text[column])) {
    return false;
  }
  size_t first = column;
  while (first && word_byte((unsigned char) text[first - 1])) { first--; }
  size_t last = column + 1;
  while (last < length && word_byte((unsigned char) text[last])) { last++; }
  *start = first;
  *end = last;
  *character = utf8_utf16_length(text, column);
  return true;
}


static bool send_definition(LspClient *client, size_t character) {
  client->definition_id = ++client->next_request_id;
  cJSON *message =
    create_message("textDocument/definition", client->definition_id);
  cJSON *params = message ? cJSON_AddObjectToObject(message, "params") : NULL;
  cJSON *text_document =
    params ? cJSON_AddObjectToObject(params, "textDocument") : NULL;
  cJSON *position = params ? cJSON_AddObjectToObject(params, "position") : NULL;
  bool success = text_document && position
    && cJSON_AddStringToObject(text_document, "uri", client->query_uri)
    && cJSON_AddNumberToObject(position, "line", (double) client->query_line)
    && cJSON_AddNumberToObject(position, "character", (double) character);
  if (success) { success = send_json(client, message); }
  cJSON_Delete(message);
  if (!success && !client->transport_error[0]) {
    set_transport_error(client, "out of memory encoding definition request");
  }
  return success;
}


static bool send_initialize(LspClient *client) {
  client->initialize_id = ++client->next_request_id;
  cJSON *message = create_message("initialize", client->initialize_id);
  cJSON *params = message ? cJSON_AddObjectToObject(message, "params") : NULL;
  cJSON *capabilities =
    params ? cJSON_AddObjectToObject(params, "capabilities") : NULL;
  cJSON *general =
    capabilities ? cJSON_AddObjectToObject(capabilities, "general") : NULL;
  cJSON *encodings =
    general ? cJSON_AddArrayToObject(general, "positionEncodings") : NULL;
  cJSON *encoding = encodings ? cJSON_CreateString("utf-16") : NULL;
  bool encoding_added = encoding && cJSON_AddItemToArray(encodings, encoding);
  if (!encoding_added) { cJSON_Delete(encoding); }
  cJSON *text_document =
    capabilities ? cJSON_AddObjectToObject(capabilities, "textDocument") : NULL;
  cJSON *definition =
    text_document ? cJSON_AddObjectToObject(text_document, "definition") : NULL;
  cJSON *client_info =
    params ? cJSON_AddObjectToObject(params, "clientInfo") : NULL;
  bool success = params && definition && client_info && encoding_added
    && cJSON_AddNullToObject(params, "processId")
    && cJSON_AddStringToObject(params, "rootUri", client->root_uri)
    && cJSON_AddTrueToObject(definition, "linkSupport")
    && cJSON_AddStringToObject(client_info, "name", "nslite");
  if (success) { success = send_json(client, message); }
  cJSON_Delete(message);
  if (!success && !client->transport_error[0]) {
    set_transport_error(client, "out of memory encoding initialize request");
  }
  return success;
}


static void clear_query(LspClient *client) {
  SDL_free(client->query_uri);
  SDL_free(client->target_path);
  client->query_uri = NULL;
  client->target_path = NULL;
  client->query_state = QUERY_NONE;
  client->definition_id = 0;
}


static void close_client(LspClient *client) {
  if (client->process) {
    update_status(client);
    if (!client->exited) {
      SDL_KillProcess(client->process, true);
      SDL_WaitProcess(client->process, true, &client->exit_code);
      client->exited = true;
    }
    SDL_DestroyProcess(client->process);
  }
  client->process = NULL;
  client->input = NULL;
  client->output = NULL;
  client->error = NULL;
  buffer_clear(&client->reads);
  buffer_clear(&client->writes);
  SDL_free(client->root_uri);
  client->root_uri = NULL;
  clear_query(client);
  while (client->documents) {
    OpenDocument *open = client->documents;
    client->documents = open->next;
    SDL_free(open->uri);
    SDL_free(open);
  }
}


static int push_transport_error(lua_State *L, LspClient *client) {
  lua_pushnil(L);
  lua_pushstring(L, client->transport_error);
  return 2;
}


static int f_start(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  lua_Integer argument_count = luaL_len(L, 1);
  if (argument_count < 1) {
    return luaL_argerror(L, 1, "expected a non-empty command argument list");
  }
  for (lua_Integer i = 1; i <= argument_count; i++) {
    lua_rawgeti(L, 1, i);
    if (lua_type(L, -1) != LUA_TSTRING) {
      lua_pop(L, 1);
      return luaL_argerror(L, 1, "command arguments must be strings");
    }
    lua_pop(L, 1);
  }
  const char *working_directory = luaL_checkstring(L, 2);
  char *root_uri = path_to_file_uri(working_directory);
  if (!root_uri) {
    return luaL_error(L, "out of memory creating LSP root URI");
  }

  const char **arguments =
    SDL_calloc((size_t) argument_count + 1, sizeof(*arguments));
  if (!arguments) {
    SDL_free(root_uri);
    return luaL_error(L, "out of memory starting language server");
  }
  for (lua_Integer i = 1; i <= argument_count; i++) {
    lua_rawgeti(L, 1, i);
    arguments[i - 1] = lua_tostring(L, -1);
    lua_pop(L, 1);
  }

  SDL_PropertiesID properties = SDL_CreateProperties();
  bool configured = properties != 0;
  if (configured) {
    configured = SDL_SetPointerProperty(
      properties, SDL_PROP_PROCESS_CREATE_ARGS_POINTER, (void *) arguments);
  }
  if (configured) {
    configured = SDL_SetStringProperty(properties,
      SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING, working_directory);
  }
  if (configured) {
    configured = SDL_SetNumberProperty(properties,
                   SDL_PROP_PROCESS_CREATE_STDIN_NUMBER, SDL_PROCESS_STDIO_APP)
      && SDL_SetNumberProperty(properties,
        SDL_PROP_PROCESS_CREATE_STDOUT_NUMBER, SDL_PROCESS_STDIO_APP)
      && SDL_SetNumberProperty(properties,
        SDL_PROP_PROCESS_CREATE_STDERR_NUMBER, SDL_PROCESS_STDIO_APP);
  }
  SDL_Process *process =
    configured ? SDL_CreateProcessWithProperties(properties) : NULL;
  char start_error[256];
  SDL_strlcpy(start_error, SDL_GetError(), sizeof(start_error));
  if (properties) { SDL_DestroyProperties(properties); }
  SDL_free(arguments);

  if (!process) {
    SDL_free(root_uri);
    lua_pushnil(L);
    lua_pushfstring(L, "failed to start language server: %s",
      start_error[0] ? start_error : "unknown process error");
    return 2;
  }

  SDL_PropertiesID process_properties = SDL_GetProcessProperties(process);
  SDL_IOStream *input = SDL_GetProcessInput(process);
  SDL_IOStream *output = SDL_GetProcessOutput(process);
  SDL_IOStream *error = SDL_GetPointerProperty(
    process_properties, SDL_PROP_PROCESS_STDERR_POINTER, NULL);
  if (!input || !output || !error) {
    SDL_strlcpy(start_error, SDL_GetError(), sizeof(start_error));
    SDL_KillProcess(process, true);
    SDL_WaitProcess(process, true, NULL);
    SDL_DestroyProcess(process);
    SDL_free(root_uri);
    lua_pushnil(L);
    lua_pushfstring(L, "failed to open language server pipes: %s",
      start_error[0] ? start_error : "unknown process error");
    return 2;
  }

  LspClient *client = lua_newuserdatauv(L, sizeof(*client), 0);
  *client = (LspClient) { 0 };
  client->process = process;
  client->input = input;
  client->output = output;
  client->error = error;
  client->root_uri = root_uri;
  luaL_setmetatable(L, API_TYPE_LSP_CLIENT);
  if (!send_initialize(client)) {
    close_client(client);
    lua_pop(L, 1);
    lua_pushnil(L);
    lua_pushliteral(L, "failed to send language server initialization");
    return 2;
  }
  return 1;
}


static int f_definition(lua_State *L) {
  LspClient *client = check_client(L);
  Document *document = document_check(L, 2);
  const char *language_id = luaL_checkstring(L, 3);
  lua_Integer requested_line = luaL_checkinteger(L, 4);
  lua_Integer requested_column = luaL_checkinteger(L, 5);
  if (!client->process) {
    lua_pushnil(L);
    lua_pushliteral(L, "language server client is closed");
    return 2;
  }
  if (!pump_client(client)) { return push_transport_error(L, client); }

  const char *filename = document_filename(document);
  size_t line_count = document_line_count(document);
  if (!filename || requested_line < 1 || (uint64_t) requested_line > line_count
    || requested_column < 1) {
    lua_pushliteral(L, "none");
    return 1;
  }
  size_t line = (size_t) requested_line - 1;
  size_t column = (size_t) requested_column - 1;
  size_t start;
  size_t end;
  size_t character;
  if (!document_word(document, line, column, &start, &end, &character)) {
    lua_pushliteral(L, "none");
    return 1;
  }

  char *uri = path_to_file_uri(filename);
  if (!uri) { return luaL_error(L, "out of memory creating document URI"); }
  uint64_t revision = document_revision(document);
  bool same_query = client->query_uri && SDL_strcmp(client->query_uri, uri) == 0
    && client->query_revision == revision && client->query_line == line
    && client->query_start == start && client->query_end == end;
  if (!same_query) {
    clear_query(client);
    client->query_uri = uri;
    uri = NULL;
    client->query_revision = revision;
    client->query_line = line;
    client->query_start = start;
    client->query_end = end;
    client->query_state = QUERY_PENDING;
  }
  SDL_free(uri);

  if (client->initialized && client->query_state == QUERY_PENDING
    && client->definition_id == 0) {
    if (!sync_document(client, document, language_id, client->query_uri)
      || !send_definition(client, character)) {
      if (!client->transport_error[0]) {
        set_transport_error(client, "failed to request definition");
      }
      return push_transport_error(L, client);
    }
  }

  if (client->query_state == QUERY_READY) {
    lua_pushliteral(L, "ready");
    lua_pushstring(L, client->target_path);
    lua_pushinteger(L, (lua_Integer) client->target_line);
    lua_pushinteger(L, (lua_Integer) client->target_character);
    lua_pushinteger(L, (lua_Integer) client->query_start + 1);
    lua_pushinteger(L, (lua_Integer) client->query_end + 1);
    return 6;
  }
  lua_pushstring(
    L, client->query_state == QUERY_MISSING ? "missing" : "pending");
  return 1;
}


static int f_resolve_position(lua_State *L) {
  Document *document = document_check(L, 1);
  lua_Integer requested_line = luaL_checkinteger(L, 2);
  lua_Integer requested_character = luaL_checkinteger(L, 3);
  size_t count = document_line_count(document);
  size_t line = requested_line < 0 ? 0 : (size_t) requested_line;
  if (line >= count) { line = count - 1; }
  size_t character = requested_character < 0 ? 0 : (size_t) requested_character;
  size_t length;
  const char *text = document_line(document, line, &length);
  size_t column = utf8_byte_offset_from_utf16(text, length, character) + 1;
  lua_pushinteger(L, (lua_Integer) line + 1);
  lua_pushinteger(L, (lua_Integer) column);
  return 2;
}


static int f_status(lua_State *L) {
  LspClient *client = check_client(L);
  if (!client->process) {
    lua_pushliteral(L, "closed");
    return 1;
  }
  update_status(client);
  if (client->exited) {
    lua_pushliteral(L, "exited");
    lua_pushinteger(L, client->exit_code);
    return 2;
  }
  lua_pushstring(L, client->initialized ? "ready" : "starting");
  return 1;
}


static int f_close(lua_State *L) {
  close_client(check_client(L));
  return 0;
}


static int f_gc(lua_State *L) {
  close_client(check_client(L));
  return 0;
}


static const luaL_Reg client_lib[] = { { "__gc", f_gc },
  { "definition", f_definition }, { "status", f_status }, { "close", f_close },
  { NULL, NULL } };


static const luaL_Reg module_lib[] = { { "start", f_start },
  { "resolve_position", f_resolve_position }, { NULL, NULL } };


int luaopen_lsp(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_LSP_CLIENT);
  luaL_setfuncs(L, client_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  luaL_newlib(L, module_lib);
  return 1;
}
