cmake_minimum_required(VERSION 3.20)
project(nsl C)

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
    set(NSLITE_SDL_TARGET PkgConfig::SDL3)
    set(NSLITE_PCRE2_TARGET PkgConfig::PCRE2)
    set(NSLITE_LUA_TARGET PkgConfig::LUA)
else()
    include(FetchContent)
    
    FetchContent_Declare(
        SDL3
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        main
        GIT_SHALLOW    TRUE
    )
    
    set(SDL_SHARED ON CACHE BOOL "" FORCE)
    set(SDL_STATIC OFF CACHE BOOL "" FORCE)
    set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
    
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
    
    set(NSLITE_SDL_TARGET SDL3::SDL3)
    set(NSLITE_PCRE2_TARGET pcre2-8-static)
    set(NSLITE_LUA_TARGET lua)
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
)

if(APPLE)
    list(APPEND NSLITE_SOURCES src/utils/macos.m)
endif()

add_executable(nsl ${NSLITE_SOURCES})
nslite_enable_strict_warnings(nsl)

target_include_directories(nsl PRIVATE src)

target_link_libraries(nsl PRIVATE
    ${NSLITE_SDL_TARGET}
    ${NSLITE_LUA_TARGET}
    ${NSLITE_PCRE2_TARGET}
    nsl_image
    nsl_stb
    nsl_cjson
)

if(APPLE)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    target_link_libraries(nsl PRIVATE ${APPKIT_FRAMEWORK})
endif()

if(UNIX)
    target_link_libraries(nsl PRIVATE m)
endif()

if(UNIX AND NOT APPLE)
    target_compile_definitions(nsl PRIVATE LUA_USE_POSIX)
elseif(WIN32)
    target_compile_definitions(nsl PRIVATE LUA_USE_POPEN)
endif()

file(GLOB_RECURSE DATA_FILES CONFIGURE_DEPENDS data/*.lua)

add_custom_target(copy_data ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/data $<TARGET_FILE_DIR:nsl>/data
    DEPENDS ${DATA_FILES}
)

add_custom_command(TARGET nsl POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/data $<TARGET_FILE_DIR:nsl>/data
)
