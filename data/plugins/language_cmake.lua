local syntax = require "core.syntax"

local symbols = {}
local function add_symbols(token_type, names)
  for _, name in ipairs(names) do
    symbols[name:lower()] = token_type
    symbols[name:upper()] = token_type
  end
end

add_symbols("keyword", {
  "if", "elseif", "else", "endif", "foreach", "endforeach", "while", "endwhile",
  "function", "endfunction", "macro", "endmacro", "return", "break", "continue",
  "include", "find_package", "find_program", "find_library", "find_file", "find_path",
  "option", "set", "unset", "list", "string", "math", "file", "configure_file",
  "cmake_minimum_required", "cmake_policy", "project", "message", "execute_process",
  "add_subdirectory", "include_guard", "mark_as_advanced", "set_property", "get_property",
})

add_symbols("function", {
  "add_executable", "add_library", "add_custom_command", "add_custom_target",
  "target_link_libraries", "target_include_directories", "target_compile_definitions",
  "target_compile_features", "target_compile_options", "target_sources", "target_properties",
  "set_target_properties", "get_target_property", "install", "enable_testing", "add_test",
})

add_symbols("literal", {
  "on", "off", "true", "false", "yes", "no", "ignore", "notfound",
  "public", "private", "interface", "debug", "release", "relwithdebinfo",
  "minsizerel", "required", "quiet", "optional",
})

syntax.add {
  files = { "CMakeLists%.txt$", "%.cmake$", "%.cmake%.in$" },
  comment = "#",
  patterns = {
    { pattern = { [=[\$<]=], ">" },       type = "keyword2" },
    { pattern = { [=[\$\{]=], [=[\}]=] }, type = "keyword2" },
    { pattern = "#.*",                     type = "comment" },
    { pattern = { '"', '"', '\\' },       type = "string" },
    { pattern = { [=[\[]=], [=[\]]=] },    type = "string" },
    { pattern = [=[\d+\.?\d*]=],          type = "number" },
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*(?=\()]=], type = "function" },
    { pattern = [=[[+\-=/\*^%<>!~|&:]]=], type = "operator" },
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*]=], type = "symbol" },
  },
  symbols = symbols,
}
