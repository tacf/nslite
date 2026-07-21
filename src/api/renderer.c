#include <limits.h>
#include "api.h"
#include "renderer.h"
#include "rencache.h"


static int check_int(lua_State *L, int index) {
  lua_Number value = luaL_checknumber(L, index);
  if (!(value >= INT_MIN && value <= INT_MAX)) {
    luaL_argerror(L, index, "number is outside the integer range");
  }
  return (int) value;
}


static uint8_t check_color_component(lua_State *L, int index) {
  lua_Number value = luaL_checknumber(L, index);
  if (!(value >= 0 && value <= UINT8_MAX)) {
    luaL_error(L, "color component must be between 0 and 255");
  }
  return (uint8_t) value;
}


static RenColor checkcolor(lua_State *L, int idx, uint8_t default_value) {
  RenColor color;
  if (lua_isnoneornil(L, idx)) {
    return (RenColor) {
      default_value, default_value, default_value, UINT8_MAX
    };
  }
  lua_rawgeti(L, idx, 1);
  lua_rawgeti(L, idx, 2);
  lua_rawgeti(L, idx, 3);
  lua_rawgeti(L, idx, 4);
  color.r = check_color_component(L, -4);
  color.g = check_color_component(L, -3);
  color.b = check_color_component(L, -2);
  color.a = lua_isnil(L, -1) ? UINT8_MAX : check_color_component(L, -1);
  lua_pop(L, 4);
  return color;
}


static int f_show_debug(lua_State *L) {
  luaL_checkany(L, 1);
  rencache_show_debug(lua_toboolean(L, 1));
  return 0;
}


static int f_get_size(lua_State *L) {
  int w, h;
  ren_get_size(&w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}


static int f_begin_frame(lua_State *L) {
  (void) L;
  rencache_begin_frame();
  return 0;
}


static int f_end_frame(lua_State *L) {
  (void) L;
  rencache_end_frame();
  return 0;
}


static int f_set_clip_rect(lua_State *L) {
  RenRect rect;
  rect.x = check_int(L, 1);
  rect.y = check_int(L, 2);
  rect.width = check_int(L, 3);
  rect.height = check_int(L, 4);
  rencache_set_clip_rect(rect);
  return 0;
}


static int f_draw_rect(lua_State *L) {
  RenRect rect;
  rect.x = check_int(L, 1);
  rect.y = check_int(L, 2);
  rect.width = check_int(L, 3);
  rect.height = check_int(L, 4);
  RenColor color = checkcolor(L, 5, 255);
  rencache_draw_rect(rect, color);
  return 0;
}


static int f_draw_text(lua_State *L) {
  RenFont **font = luaL_checkudata(L, 1, API_TYPE_FONT);
  const char *text = luaL_checkstring(L, 2);
  int x = check_int(L, 3);
  int y = check_int(L, 4);
  RenColor color = checkcolor(L, 5, 255);
  x = rencache_draw_text(*font, text, x, y, color);
  lua_pushnumber(L, x);
  return 1;
}


static const luaL_Reg lib[] = {
  { "show_debug",    f_show_debug    },
  { "get_size",      f_get_size      },
  { "begin_frame",   f_begin_frame   },
  { "end_frame",     f_end_frame     },
  { "set_clip_rect", f_set_clip_rect },
  { "draw_rect",     f_draw_rect     },
  { "draw_text",     f_draw_text     },
  { NULL,            NULL            }
};


int luaopen_renderer_font(lua_State *L);

int luaopen_renderer(lua_State *L) {
  luaL_newlib(L, lib);
  luaopen_renderer_font(L);
  lua_setfield(L, -2, "font");
  return 1;
}
