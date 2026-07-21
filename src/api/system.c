#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "api.h"
#include "rencache.h"

extern SDL_Window *window;


static double get_scale(void) {
  double scale = SDL_GetWindowDisplayScale(window);
  return scale > 0.0 ? scale : 1.0;
}


static const char* button_name(int button) {
  switch (button) {
    case 1  : return "left";
    case 2  : return "middle";
    case 3  : return "right";
    default : return "?";
  }
}


static char* key_name(
  char *destination, size_t destination_size, SDL_Keycode symbol
) {
  SDL_strlcpy(destination, SDL_GetKeyName(symbol), destination_size);
  char *p = destination;
  while (*p) {
    *p = (char) tolower((unsigned char) *p);
    p++;
  }
  return destination;
}


static int f_poll_event(lua_State *L) {
  char buf[16];
  SDL_Event e;
  double scale = get_scale();

  while (SDL_PollEvent(&e)) {
    switch (e.type) {
    case SDL_EVENT_QUIT:
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      lua_pushstring(L, "quit");
      return 1;

    case SDL_EVENT_WINDOW_RESIZED:
      lua_pushstring(L, "resized");
      lua_pushnumber(L, e.window.data1 * scale);
      lua_pushnumber(L, e.window.data2 * scale);
      return 3;

    case SDL_EVENT_WINDOW_EXPOSED:
      rencache_invalidate();
      lua_pushstring(L, "exposed");
      return 1;

    case SDL_EVENT_WINDOW_FOCUS_GAINED:
      SDL_FlushEvent(SDL_EVENT_KEY_DOWN);
      break;

    case SDL_EVENT_DROP_FILE:
      lua_pushstring(L, "filedropped");
      lua_pushstring(L, e.drop.data);
      lua_pushnumber(L, e.drop.x * scale);
      lua_pushnumber(L, e.drop.y * scale);
      return 4;

    case SDL_EVENT_KEY_DOWN:
      lua_pushstring(L, "keypressed");
      lua_pushstring(L, key_name(buf, sizeof(buf), e.key.key));
      return 2;

    case SDL_EVENT_KEY_UP:
      lua_pushstring(L, "keyreleased");
      lua_pushstring(L, key_name(buf, sizeof(buf), e.key.key));
      return 2;

    case SDL_EVENT_TEXT_INPUT:
      lua_pushstring(L, "textinput");
      lua_pushstring(L, e.text.text);
      return 2;

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
      if (e.button.button == 1) { SDL_CaptureMouse(true); }
      lua_pushstring(L, "mousepressed");
      lua_pushstring(L, button_name(e.button.button));
      lua_pushnumber(L, e.button.x * scale);
      lua_pushnumber(L, e.button.y * scale);
      lua_pushnumber(L, e.button.clicks);
      return 5;

    case SDL_EVENT_MOUSE_BUTTON_UP:
      if (e.button.button == 1) { SDL_CaptureMouse(false); }
      lua_pushstring(L, "mousereleased");
      lua_pushstring(L, button_name(e.button.button));
      lua_pushnumber(L, e.button.x * scale);
      lua_pushnumber(L, e.button.y * scale);
      return 4;

    case SDL_EVENT_MOUSE_MOTION:
      lua_pushstring(L, "mousemoved");
      lua_pushnumber(L, e.motion.x * scale);
      lua_pushnumber(L, e.motion.y * scale);
      lua_pushnumber(L, e.motion.xrel * scale);
      lua_pushnumber(L, e.motion.yrel * scale);
      return 5;

    case SDL_EVENT_MOUSE_WHEEL:
      lua_pushstring(L, "mousewheel");
      lua_pushnumber(L, e.wheel.y);
      return 2;

    default:
      break;
    }
  }

  return 0;
}


static int f_wait_event(lua_State *L) {
  double milliseconds = luaL_checknumber(L, 1) * 1000.0;
  Sint32 timeout = 0;
  if (milliseconds < 0.0) {
    timeout = -1;
  } else if (milliseconds >= INT32_MAX) {
    timeout = INT32_MAX;
  } else if (milliseconds >= 0.0) {
    timeout = (Sint32) milliseconds;
  }
  lua_pushboolean(L, SDL_WaitEventTimeout(NULL, timeout));
  return 1;
}


static SDL_Cursor* cursor_cache[SDL_SYSTEM_CURSOR_COUNT];

static const char *cursor_opts[] = {
  "arrow",
  "ibeam",
  "sizeh",
  "sizev",
  "hand",
  NULL
};

static const int cursor_enums[] = {
  SDL_SYSTEM_CURSOR_DEFAULT,
  SDL_SYSTEM_CURSOR_TEXT,
  SDL_SYSTEM_CURSOR_EW_RESIZE,
  SDL_SYSTEM_CURSOR_NS_RESIZE,
  SDL_SYSTEM_CURSOR_POINTER
};

static int f_set_cursor(lua_State *L) {
  int opt = luaL_checkoption(L, 1, "arrow", cursor_opts);
  int n = cursor_enums[opt];
  SDL_Cursor *cursor = cursor_cache[n];
  if (!cursor) {
    cursor = SDL_CreateSystemCursor(n);
    cursor_cache[n] = cursor;
  }
  SDL_SetCursor(cursor);
  return 0;
}


static int f_set_window_title(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  SDL_SetWindowTitle(window, title);
  return 0;
}


static const char *window_opts[] = { "normal", "maximized", "fullscreen", 0 };
enum { WIN_NORMAL, WIN_MAXIMIZED, WIN_FULLSCREEN };

static int f_set_window_mode(lua_State *L) {
  int n = luaL_checkoption(L, 1, "normal", window_opts);
  SDL_SetWindowFullscreen(window, n == WIN_FULLSCREEN);
  if (n == WIN_NORMAL) { SDL_RestoreWindow(window); }
  if (n == WIN_MAXIMIZED) { SDL_MaximizeWindow(window); }
  return 0;
}


static int f_window_has_focus(lua_State *L) {
  SDL_WindowFlags flags = SDL_GetWindowFlags(window);
  lua_pushboolean(L, flags & SDL_WINDOW_INPUT_FOCUS);
  return 1;
}


static int f_show_confirm_dialog(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  const char *msg = luaL_checkstring(L, 2);

  SDL_MessageBoxButtonData buttons[] = {
    { SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, 1, "Yes" },
    { SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT, 0, "No" },
  };
  SDL_MessageBoxData data = {
    .flags = SDL_MESSAGEBOX_WARNING,
    .title = title,
    .message = msg,
    .numbuttons = 2,
    .buttons = buttons,
  };
  int buttonid;
  SDL_ShowMessageBox(&data, &buttonid);
  lua_pushboolean(L, buttonid == 1);
  return 1;
}


typedef struct {
  lua_State *L;
  int count;
} ListDirData;


static SDL_EnumerationResult SDLCALL list_dir_entry(
  void *userdata, const char *dirname, const char *fname
) {
  (void) dirname;
  ListDirData *data = userdata;
  if (strcmp(fname, ".") == 0 || strcmp(fname, "..") == 0) {
    return SDL_ENUM_CONTINUE;
  }
  lua_pushstring(data->L, fname);
  lua_rawseti(data->L, -2, ++data->count);
  return SDL_ENUM_CONTINUE;
}


static int f_list_dir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  lua_newtable(L);
  ListDirData data = { L, 0 };
  if (!SDL_EnumerateDirectory(path, list_dir_entry, &data)) {
    lua_pop(L, 1);
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }
  return 1;
}


static bool path_is_absolute(const char *path) {
  return path[0] == '/' || path[0] == '\\'
      || (isalpha((unsigned char) path[0]) && path[1] == ':');
}


static int f_absolute_path(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  char *cwd = NULL;
  char *res = NULL;
  if (path_is_absolute(path)) {
    res = SDL_strdup(path);
  } else {
    cwd = SDL_GetCurrentDirectory();
    if (cwd) { SDL_asprintf(&res, "%s%s", cwd, path); }
  }
  SDL_free(cwd);
  if (!res || !SDL_GetPathInfo(res, NULL)) {
    SDL_free(res);
    return 0;
  }
  lua_pushstring(L, res);
  SDL_free(res);
  return 1;
}


static int f_get_file_info(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

  SDL_PathInfo info;
  if (!SDL_GetPathInfo(path, &info)) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }

  lua_newtable(L);
  lua_pushnumber(L, (lua_Number) info.modify_time);
  lua_setfield(L, -2, "modified");

  lua_pushnumber(L, (lua_Number) info.size);
  lua_setfield(L, -2, "size");

  if (info.type == SDL_PATHTYPE_FILE) {
    lua_pushstring(L, "file");
  } else if (info.type == SDL_PATHTYPE_DIRECTORY) {
    lua_pushstring(L, "dir");
  } else {
    lua_pushnil(L);
  }
  lua_setfield(L, -2, "type");

  return 1;
}


static int f_get_clipboard(lua_State *L) {
  const char *text = SDL_GetClipboardText();
  if (!text) { return 0; }
  lua_pushstring(L, text);
  return 1;
}


static int f_set_clipboard(lua_State *L) {
  const char *text = luaL_checkstring(L, 1);
  SDL_SetClipboardText(text);
  return 0;
}


static int f_get_time(lua_State *L) {
  double n = (double) SDL_GetPerformanceCounter()
    / (double) SDL_GetPerformanceFrequency();
  lua_pushnumber(L, n);
  return 1;
}


static int f_sleep(lua_State *L) {
  double milliseconds = luaL_checknumber(L, 1) * 1000.0;
  if (milliseconds > 0.0) {
    Uint32 delay = milliseconds > UINT32_MAX
      ? UINT32_MAX
      : (Uint32) milliseconds;
    SDL_Delay(delay);
  }
  return 0;
}


static int f_exec(lua_State *L) {
  const char *cmd = luaL_checkstring(L, 1);
  int res = system(cmd);
  (void) res;
  return 0;
}


static int f_fuzzy_match(lua_State *L) {
  const char *str = luaL_checkstring(L, 1);
  const char *ptn = luaL_checkstring(L, 2);
  int score = 0;
  int run = 0;

  while (*str && *ptn) {
    while (*str == ' ') { str++; }
    while (*ptn == ' ') { ptn++; }
    if (tolower(*str) == tolower(*ptn)) {
      score += run * 10 - (*str != *ptn);
      run++;
      ptn++;
    } else {
      score -= 10;
      run = 0;
    }
    str++;
  }
  if (*ptn) { return 0; }

  lua_pushnumber(L, score - (int) strlen(str));
  return 1;
}


static const luaL_Reg lib[] = {
  { "poll_event",          f_poll_event          },
  { "wait_event",          f_wait_event          },
  { "set_cursor",          f_set_cursor          },
  { "set_window_title",    f_set_window_title    },
  { "set_window_mode",     f_set_window_mode     },
  { "window_has_focus",    f_window_has_focus    },
  { "show_confirm_dialog", f_show_confirm_dialog },
  { "list_dir",            f_list_dir            },
  { "absolute_path",       f_absolute_path       },
  { "get_file_info",       f_get_file_info       },
  { "get_clipboard",       f_get_clipboard       },
  { "set_clipboard",       f_set_clipboard       },
  { "get_time",            f_get_time            },
  { "sleep",               f_sleep               },
  { "exec",                f_exec                },
  { "fuzzy_match",         f_fuzzy_match         },
  { NULL, NULL }
};


int luaopen_system(lua_State *L) {
  luaL_newlib(L, lib);
  return 1;
}
