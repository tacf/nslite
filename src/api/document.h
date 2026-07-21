#ifndef DOCUMENT_H
#define DOCUMENT_H

#include <stddef.h>
#include <stdint.h>
#include "lua.h"


typedef struct Document Document;


Document *document_check(lua_State *L, int index);
const char *document_filename(const Document *document);
uint64_t document_revision(const Document *document);
size_t document_line_count(const Document *document);
const char *document_line(
  const Document *document, size_t line, size_t *byte_count);


#endif
