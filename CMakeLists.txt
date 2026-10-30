cmake_minimum_required(VERSION 3.20)
project(nsl C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(APPLE)
    enable_language(OBJC)
endif()

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

function(nslite_enable_strict_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /WX)
    elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endfunction()

option(NSLITE_USE_SYSTEM_LIBS "Use SDL3, PCRE2, and Lua from the system" OFF)

if(NSLITE_USE_SYSTEM_LIBS)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SDL3 REQUIRED IMPORTED_TARGET sdl3)
    pkg_check_modules(PCRE2 REQUIRED IMPORTED_TARGET libpcre2-8)
    pkg_check_modules(LUA REQUIRED IMPORTED_TARGET lua>=5.5)
    # 1.5 just to ensure that we don't pull the deprecated stuff we're not using
    pkg_check_modules(GIT REQUIRED IMPORTED_TARGET libgit2>=1.5)
    set(NSLITE_SDL_TARGET PkgConfig::SDL3)
    set(NSLITE_PCRE2_TARGET PkgConfig::PCRE2)
    set(NSLITE_LUA_TARGET PkgConfig::LUA)
    set(NSLITE_GIT_TARGET PkgConfig::GIT)
    set(NSLITE_GIT_INCLUDE_DIRS "")
else()
    include(FetchContent)

    FetchContent_Declare(
        SDL3
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        main
        GIT_SHALLOW    TRUE
    )

    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_LEAN_AND_MEAN ON CACHE BOOL "" FORCE)
    set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)

    set(SDL_AUDIO OFF CACHE BOOL "" FORCE)
    set(SDL_RENDER OFF CACHE BOOL "" FORCE)
    set(SDL_GPU OFF CACHE BOOL "" FORCE)
    set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
    set(SDL_JOYSTICK OFF CACHE BOOL "" FORCE)
    set(SDL_HAPTIC OFF CACHE BOOL "" FORCE)
    set(SDL_HIDAPI OFF CACHE BOOL "" FORCE)
    set(SDL_SENSOR OFF CACHE BOOL "" FORCE)
    # Only to compile in X11's visual selection; without GLX it forces the
    # default depth-24 visual (XRGB8888, no alpha). Rendering stays software.
    set(SDL_OPENGL ON CACHE BOOL "" FORCE)
    set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
    set(SDL_VULKAN OFF CACHE BOOL "" FORCE)
    set(SDL_DBUS OFF CACHE BOOL "" FORCE)
    set(SDL_LIBUDEV OFF CACHE BOOL "" FORCE)

    FetchContent_MakeAvailable(SDL3)

    set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
    set(PCRE2_BUILD_PCRE2_8 ON CACHE BOOL "" FORCE)
    set(PCRE2_BUILD_PCRE2_16 OFF CACHE BOOL "" FORCE)
    set(PCRE2_BUILD_PCRE2_32 OFF CACHE BOOL "" FORCE)
    set(PCRE2_BUILD_PCRE2GREP OFF CACHE BOOL "" FORCE)
    set(PCRE2_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(PCRE2_SUPPORT_JIT OFF CACHE BOOL "" FORCE)
    set(PCRE2_SHOW_REPORT OFF CACHE BOOL "" FORCE)

    FetchContent_Declare(
        PCRE2
        GIT_REPOSITORY https://github.com/PCRE2Project/pcre2.git
        GIT_TAG        pcre2-10.47
        GIT_SHALLOW    TRUE
    )

    FetchContent_MakeAvailable(PCRE2)

    FetchContent_Declare(
        lua
        URL            https://www.lua.org/ftp/lua-5.5.0.tar.gz
        URL_HASH       SHA256=57ccc32bbbd005cab75bcc52444052535af691789dba2b9016d5c50640d68b3d
    )

    FetchContent_MakeAvailable(lua)

    file(GLOB LUA_SOURCES ${lua_SOURCE_DIR}/src/*.c)
    list(FILTER LUA_SOURCES EXCLUDE REGEX "lua\\.c$")
    list(FILTER LUA_SOURCES EXCLUDE REGEX "luac\\.c$")

    add_library(lua STATIC ${LUA_SOURCES})
    target_include_directories(lua PUBLIC ${lua_SOURCE_DIR}/src)
    set_target_properties(lua PROPERTIES POSITION_INDEPENDENT_CODE ON)

    if(UNIX AND NOT APPLE)
        target_compile_definitions(lua PRIVATE LUA_USE_POSIX)
    elseif(WIN32)
        target_compile_definitions(lua PRIVATE LUA_USE_POPEN)
    endif()

    # we only read local repos, so drop the network transports and their deps
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(BUILD_CLI OFF CACHE BOOL "" FORCE)
    set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(BUILD_FUZZERS OFF CACHE BOOL "" FORCE)
    set(USE_SSH OFF CACHE STRING "" FORCE)
    set(USE_HTTPS OFF CACHE STRING "" FORCE)
    # otherwise libgit2 links whatever system PCRE2/PCRE it finds
    set(REGEX_BACKEND "builtin" CACHE STRING "" FORCE)

    FetchContent_Declare(
        libgit
        URL            https://github.com/libgit2/libgit2/archive/refs/tags/v1.9.6.tar.gz
        URL_HASH       SHA256=a88a42a4ea9bdab7aa8686eead3bf7d9c6dd74529caca16ab22eaa92433d31d9
    )

    # libgit2 runs its feature probes without _GNU_SOURCE and then expects the
    # glibc extensions they missed
    set(_nsl_saved_req_defs ${CMAKE_REQUIRED_DEFINITIONS})
    set(CMAKE_REQUIRED_DEFINITIONS ${CMAKE_REQUIRED_DEFINITIONS} -D_GNU_SOURCE)
    FetchContent_MakeAvailable(libgit)
    set(CMAKE_REQUIRED_DEFINITIONS ${_nsl_saved_req_defs})

    set(NSLITE_SDL_TARGET SDL3::SDL3)
    set(NSLITE_PCRE2_TARGET pcre2-8-static)
    set(NSLITE_LUA_TARGET lua)
    set(NSLITE_GIT_TARGET libgit2package)
    set(NSLITE_GIT_INCLUDE_DIRS ${libgit_SOURCE_DIR}/include)
endif()

set(NSLITE_IMAGE_SOURCES
    src/lib/nanosvg/nanosvg.c
    src/lib/stb/stb_image.c
)
add_library(nsl_image STATIC ${NSLITE_IMAGE_SOURCES})
if(MSVC)
    target_compile_options(nsl_image PRIVATE /O1)
elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(nsl_image PRIVATE -Os)
endif()

add_library(nsl_stb STATIC src/lib/stb/stb_truetype.c)

add_library(nsl_cjson STATIC src/lib/cjson/cJSON.c)
target_include_directories(nsl_cjson PUBLIC src/lib/cjson)
target_compile_definitions(nsl_cjson PRIVATE CJSON_NESTING_LIMIT=64)

set(NSLITE_SOURCES
    src/main.c
    src/renderer.c
    src/rencache.c
    src/utils/path.c
    src/utils/utf8.c
    src/utils/window.c
    src/api/api.c
    src/api/renderer.c
    src/api/renderer_font.c
    src/api/renderer_image.c
    src/api/system.c
    src/api/document.c
    src/api/syntax.c
    src/api/lsp.c
    src/api/git.c
)

if(APPLE)
    list(APPEND NSLITE_SOURCES src/utils/macos.m)
endif()

add_executable(nsl ${NSLITE_SOURCES})
nslite_enable_strict_warnings(nsl)

target_include_directories(nsl PRIVATE src)
target_include_directories(nsl PRIVATE ${NSLITE_GIT_INCLUDE_DIRS})

# hide libgit2's deprecated API so it cannot be used by accident
target_compile_definitions(nsl PRIVATE GIT_DEPRECATE_HARD)

target_link_libraries(nsl PRIVATE
    ${NSLITE_SDL_TARGET}
    ${NSLITE_LUA_TARGET}
    ${NSLITE_PCRE2_TARGET}
    ${NSLITE_GIT_TARGET}
    nsl_image
    nsl_stb
    nsl_cjson
)

if(APPLE)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    target_link_libraries(nsl PRIVATE ${APPKIT_FRAMEWORK})

    # SDL_cocoamouse.m always references GCMouse, but SDL only links
    # GameController when SDL_JOYSTICK is on, which we disable.
    # So enjoyable to support cross OS builds :'D
    find_library(GAMECONTROLLER_FRAMEWORK GameController REQUIRED)
    target_link_libraries(nsl PRIVATE ${GAMECONTROLLER_FRAMEWORK})
endif()

if(UNIX)
    target_link_libraries(nsl PRIVATE m)
endif()

if(UNIX AND NOT APPLE)
    # _DEFAULT_SOURCE exposes daemon(3); glibc keys struct layouts off the
    # feature macros, so it has to apply to every TU, not just main.c
    target_compile_definitions(nsl PRIVATE LUA_USE_POSIX _DEFAULT_SOURCE)
elseif(WIN32)
    target_compile_definitions(nsl PRIVATE LUA_USE_POPEN)
endif()

file(GLOB_RECURSE DATA_FILES CONFIGURE_DEPENDS data/*.lua)

add_custom_target(copy_data ALL
    COMMAND ${CMAKE_COMMAND} -E rm -rf $<TARGET_FILE_DIR:nsl>/data
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/data $<TARGET_FILE_DIR:nsl>/data
    DEPENDS ${DATA_FILES}
)

add_dependencies(nsl copy_data)
