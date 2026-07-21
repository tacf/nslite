#ifndef API_H
#define API_H

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define API_TYPE_FONT "Font"
#define API_TYPE_DOCUMENT "Document"
#define API_TYPE_DOCUMENT_SYNTAX "DocumentSyntax"
#define API_TYPE_LSP_CLIENT "LspClient"

void api_load_libs(lua_State *L);

#endif
