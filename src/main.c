#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>
#include "api/api.h"
#include "renderer.h"


SDL_Window *window;


static double get_scale(void) {
  float s = SDL_GetWindowDisplayScale(window);
  return s > 0 ? s : 1.0;
}



static void get_exe_filename(const char *argv0, char *buf, size_t size) {
  const char *basename = strrchr(argv0, '/');
  const char *windows_basename = strrchr(argv0, '\\');
  if (!basename || (windows_basename && windows_basename > basename)) {
    basename = windows_basename;
  }
  basename = basename ? basename + 1 : argv0;

  const char *basepath = SDL_GetBasePath();
  int written = basepath
    ? SDL_snprintf(buf, size, "%s%s", basepath, basename)
    : -1;
  if (written >= 0 && (size_t) written < size) { return; }

  SDL_strlcpy(buf, argv0, size);
}


static void init_window_icon(void) {
  #include "../icon.inl"
  (void) icon_rgba_len;
  SDL_Surface *surf = SDL_CreateSurfaceFrom(
    64, 64,
    SDL_PIXELFORMAT_RGBA32,
    icon_rgba,
    64 * 4);
  SDL_SetWindowIcon(window, surf);
  SDL_DestroySurface(surf);
}


int main(int argc, char **argv) {
  SDL_Init(SDL_INIT_VIDEO);
  SDL_EnableScreenSaver();

  SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
  SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");

  const SDL_DisplayMode *dm = SDL_GetCurrentDisplayMode(SDL_GetPrimaryDisplay());
  int dw = dm ? dm->w : 1280;
  int dh = dm ? dm->h : 720;

  window = SDL_CreateWindow(
    "", dw * 4 / 5, dh * 4 / 5,
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!window) {
    fprintf(stderr, "Failed to create window: %s\n", SDL_GetError());
    return EXIT_FAILURE;
  }
  SDL_StartTextInput(window);
  init_window_icon();
  ren_init(window);


  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  api_load_libs(L);


  lua_newtable(L);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i + 1);
  }
  lua_setglobal(L, "ARGS");

  lua_pushstring(L, "1.11");
  lua_setglobal(L, "VERSION");

  lua_pushstring(L, SDL_GetPlatform());
  lua_setglobal(L, "PLATFORM");

  lua_pushnumber(L, get_scale());
  lua_setglobal(L, "SCALE");

  char exename[2048];
  get_exe_filename(argv[0], exename, sizeof(exename));
  lua_pushstring(L, exename);
  lua_setglobal(L, "EXEFILE");


  (void) luaL_dostring(L,
    "local core\n"
    "xpcall(function()\n"
    "  SCALE = tonumber(os.getenv(\"LITE_SCALE\")) or SCALE\n"
    "  PATHSEP = package.config:sub(1, 1)\n"
    "  EXEDIR = EXEFILE:match(\"^(.+)[/\\\\].*$\")\n"
    "  BUNDLED_USERDIR = EXEDIR .. '/data/user'\n"
    "  local config_home = os.getenv('XDG_CONFIG_HOME')\n"
    "  if not config_home or config_home == '' then\n"
    "    if PLATFORM == 'Windows' then\n"
    "      config_home = os.getenv('APPDATA')\n"
    "    elseif PLATFORM == 'macOS' then\n"
    "      local home = os.getenv('HOME')\n"
    "      config_home = home and home .. '/Library/Application Support'\n"
    "    else\n"
    "      local home = os.getenv('HOME')\n"
    "      config_home = home and home .. '/.config'\n"
    "    end\n"
    "  end\n"
    "  USERDIR = BUNDLED_USERDIR\n"
    "  if config_home and config_home ~= '' then\n"
    "    local candidate = config_home .. '/nslite'\n"
    "    local f = io.open(candidate .. '/init.lua', 'rb')\n"
    "    if f then\n"
    "      f:close()\n"
    "      USERDIR = candidate\n"
    "    end\n"
    "  end\n"
    "  package.path = EXEDIR .. '/data/?.lua;' .. package.path\n"
    "  package.path = EXEDIR .. '/data/?/init.lua;' .. package.path\n"
    "  package.path = package.path .. USERDIR .. '/?.lua;'\n"
    "  package.path = package.path .. USERDIR .. '/?/init.lua;'\n"
    "  core = require('core')\n"
    "  core.init()\n"
    "  core.run()\n"
    "end, function(err)\n"
    "  print('Error: ' .. tostring(err))\n"
    "  print(debug.traceback(nil, 2))\n"
    "  if core and core.on_error then\n"
    "    pcall(core.on_error, err)\n"
    "  end\n"
    "  os.exit(1)\n"
    "end)");


  lua_close(L);
  SDL_DestroyWindow(window);
  SDL_Quit();

  return EXIT_SUCCESS;
}
