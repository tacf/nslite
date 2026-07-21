#ifndef API_SYNTAX_H
#define API_SYNTAX_H

#include <stdbool.h>
#include <stddef.h>
#include "api.h"


typedef struct DocumentSyntax DocumentSyntax;


/* Token type strings are owned by the associated DocumentSyntax. */
typedef struct {
  const char *type;
  size_t offset;
  size_t length;
} DocumentToken;


/* Each document line owns its token array and carries state to the next line. */
typedef struct {
  DocumentToken *tokens;
  size_t token_count;
  size_t token_capacity;
  size_t end_state;
} DocumentTokenLine;


DocumentSyntax *document_syntax_check(lua_State *L, int index);
bool document_syntax_tokenize_line(
  DocumentSyntax *syntax,
  const char *text,
  size_t text_length,
  size_t start_state,
  DocumentTokenLine *line,
  int *error_code
);
void document_token_line_destroy(DocumentTokenLine *line);
const char *document_syntax_error_message(
  int error_code, char *buffer, size_t buffer_size
);
int document_syntax_compile(lua_State *L);
void document_syntax_register(lua_State *L);

#endif
