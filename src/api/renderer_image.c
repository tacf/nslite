#include "api.h"
#include "renderer.h"
#include "rencache.h"


static int f_load(lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  RenImage **self = lua_newuserdata(L, sizeof(*self));
  luaL_setmetatable(L, API_TYPE_IMAGE);
  *self = ren_load_image(filename);
  if (!*self) {
    return luaL_error(L, "failed to load image '%s': %s", filename,
      SDL_GetError());
  }
  return 1;
}


static int f_gc(lua_State *L) {
  RenImage **self = luaL_checkudata(L, 1, API_TYPE_IMAGE);
  if (*self) {
    rencache_free_image(*self);
    *self = NULL;
  }
  return 0;
}


static int f_get_width(lua_State *L) {
  RenImage **self = luaL_checkudata(L, 1, API_TYPE_IMAGE);
  lua_pushinteger(L, ren_get_image_width(*self));
  return 1;
}


static int f_get_height(lua_State *L) {
  RenImage **self = luaL_checkudata(L, 1, API_TYPE_IMAGE);
  lua_pushinteger(L, ren_get_image_height(*self));
  return 1;
}


static int f_new_from_rgba(lua_State *L) {
  int width = (int) luaL_checkinteger(L, 1);
  int height = (int) luaL_checkinteger(L, 2);
  size_t data_len;
  const char *data = luaL_checklstring(L, 3, &data_len);
  RenImage **self = lua_newuserdata(L, sizeof(*self));
  luaL_setmetatable(L, API_TYPE_IMAGE);
  *self = ren_new_image_from_rgba(width, height, data, data_len);
  if (!*self) {
    return luaL_error(L, "invalid image data for %dx%d", width, height);
  }
  return 1;
}


static const luaL_Reg lib[] = {
  { "__gc",         f_gc           },
  { "load",         f_load         },
  { "new_from_rgba", f_new_from_rgba },
  { "get_width",    f_get_width    },
  { "get_height",   f_get_height   },
  { NULL, NULL }
};


int luaopen_renderer_image(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_IMAGE);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
