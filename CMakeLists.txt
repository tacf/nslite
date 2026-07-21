cmake_minimum_required(VERSION 3.20)
project(nsl C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

function(nslite_enable_strict_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /WX)
    elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endfunction()

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

FetchContent_Declare(
    lua
    URL            https://www.lua.org/ftp/lua-5.5.0.tar.gz
    URL_HASH       SHA256=57ccc32bbbd005cab75bcc52444052535af691789dba2b9016d5c50640d68b3d
)

FetchContent_GetProperties(lua)
if(NOT lua_POPULATED)
    FetchContent_Populate(lua)
endif()

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

file(GLOB_RECURSE STB_SOURCES CONFIGURE_DEPENDS src/lib/stb/*.c)
add_library(nsl_stb STATIC ${STB_SOURCES})

set(NSLITE_SOURCES
    src/main.c
    src/renderer.c
    src/rencache.c
    src/api/api.c
    src/api/renderer.c
    src/api/renderer_font.c
    src/api/system.c
    src/api/document.c
)

add_executable(nsl ${NSLITE_SOURCES})
nslite_enable_strict_warnings(nsl)

target_include_directories(nsl PRIVATE src)

target_link_libraries(nsl PRIVATE SDL3::SDL3 lua nsl_stb)

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
