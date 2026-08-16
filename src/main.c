#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>
#include "api/api.h"
#include "renderer.h"
#include "utils/window.h"
#ifdef __APPLE__
#include "utils/macos.h"
#endif
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
#ifdef __APPLE__
#include <spawn.h>
#include <mach-o/dyld.h>
#include <fcntl.h>
#include <limits.h>
extern char **environ;
#endif


/* Windows and macOS re-exec themselves and set this to mark the second copy.
   Exporting it by hand keeps nsl attached to the shell on every platform. */
static int skip_detach(void) {
#ifdef _WIN32
  return GetEnvironmentVariableW(L"NSLITE_DETACHED", NULL, 0) != 0;
#else
  return getenv("NSLITE_DETACHED") != NULL;
#endif
}


static int detach_self(int argc, char **argv) {
  // TODO: i think we need to fix this to actually open a folder project
  (void) argc;
  (void) argv;

  if (skip_detach()) return 0;

#ifdef _WIN32
  SetEnvironmentVariableW(L"NSLITE_DETACHED", L"1");

  wchar_t *cmd =
    _wcsdup(GetCommandLineW()); /* CreateProcessW may write to it */
  STARTUPINFOW si = { .cb = sizeof si };
  PROCESS_INFORMATION pi;

  BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, FALSE,
    DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, NULL, NULL, &si,
    &pi); /* NULL env = inherit, marker included */
  free(cmd);
  if (!ok) return -1;

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  ExitProcess(0); /* parent exits, shell gets its prompt back */
#elif defined(__APPLE__)
  // daemon(3) is fork() without exec(). On macOS that's unsafe once AppKit/
  // Metal are loaded (dyld loads them before main() runs): if fork() lands
  // while one of their background threads is mid class-init, the child loses
  // that thread and macOS aborts it on purpose rather than risk a deadlock
  // (see objc4's forkInitialize.m; same bug kills `qemu -daemonize` on macOS).
  //
  // posix_spawn() avoids this by starting a fresh process instead of cloning.
  // POSIX_SPAWN_SETSID and the setup below just replicate what daemon(1, 0)
  // does: detach from the terminal and send stdio to /dev/null.
  //
  // TLDR; we so fast macOS startup goes kaboom!!! and thinks there's something
  // wrong so it kills of the process. ObjC code can't run before macOS does
  // ... things :D
  // Ty Apple for all the fish!! Hopefully this works :fingers_crossed:

  setenv("NSLITE_DETACHED", "1", 1);

  char exe_path[PATH_MAX];
  uint32_t exe_path_size = sizeof(exe_path);
  if (_NSGetExecutablePath(exe_path, &exe_path_size) != 0) {
    fprintf(stderr, "Failed to resolve executable path\n");
    return 1;
  }

  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_addopen(
    &actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_addopen(
    &actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
  posix_spawn_file_actions_addopen(
    &actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  posix_spawnattr_setflags(
    &attr, POSIX_SPAWN_SETSID); /* detach from controlling terminal */

  pid_t pid;
  int res = posix_spawn(&pid, exe_path, &actions, &attr, argv, environ);

  posix_spawn_file_actions_destroy(&actions);
  posix_spawnattr_destroy(&attr);

  if (res != 0) {
    fprintf(stderr, "posix_spawn: %s\n", strerror(res));
    return 1;
  }
  _exit(0); /* parent exits, shell gets its prompt back */
#else
  // daemon(3) detaches us from the controlling terminal; plain fork() is
  // safe here since, unlike on macOS(see above).
  if (daemon(1, 0) < 0) {
    perror("daemon");
    return 1;
  }
  return 0;
#endif
}


SDL_Window *window;


static void get_exe_filename(const char *argv0, char *buf, size_t size) {
  const char *basename = strrchr(argv0, '/');
  const char *windows_basename = strrchr(argv0, '\\');
  if (!basename || (windows_basename && windows_basename > basename)) {
    basename = windows_basename;
  }
  basename = basename ? basename + 1 : argv0;

  const char *basepath = SDL_GetBasePath();
  int written =
    basepath ? SDL_snprintf(buf, size, "%s%s", basepath, basename) : -1;
  if (written >= 0 && (size_t) written < size) { return; }

  SDL_strlcpy(buf, argv0, size);
}


static void init_window_icon(void) {
#include "../icon.inl"
  (void) icon_rgba_len;
  SDL_Surface *surf =
    SDL_CreateSurfaceFrom(64, 64, SDL_PIXELFORMAT_RGBA32, icon_rgba, 64 * 4);
  SDL_SetWindowIcon(window, surf);
  SDL_DestroySurface(surf);
}


int main(int argc, char **argv) {
  if (detach_self(argc, argv) != 0) return 1;

  SDL_Init(SDL_INIT_VIDEO);
  SDL_EnableScreenSaver();

  SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
  SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");

  const SDL_DisplayMode *dm =
    SDL_GetCurrentDisplayMode(SDL_GetPrimaryDisplay());
  int dw = dm ? dm->w : 1280;
  int dh = dm ? dm->h : 720;

  window = SDL_CreateWindow("", dw * 4 / 5, dh * 4 / 5,
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!window) {
    fprintf(stderr, "Failed to create window: %s\n", SDL_GetError());
    return EXIT_FAILURE;
  }
#ifdef __APPLE__
  macos_disable_native_close_shortcut();
#endif
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

  lua_pushnumber(L, window_get_scale(window));
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
    "  if system and system.show_error_dialog then\n"
    "    system.show_error_dialog('nslite failed to start',\n"
    "      tostring(err) .. '\\n\\n' .. (debug.traceback(nil, 2) or ''))\n"
    "  end\n"
    "  if not core then\n"
    "    local fp = io.open(EXEDIR .. '/error.txt', 'wb')\n"
    "    if fp then\n"
    "      fp:write('Error: ' .. tostring(err) .. '\\n')\n"
    "      fp:write(debug.traceback(nil, 2) or '')\n"
    "      fp:close()\n"
    "    end\n"
    "  end\n"
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
