local syntax = require "core.syntax"

local symbols = {}
for _, name in ipairs {
  "if", "else", "not", "for", "do", "in", "equ", "neq", "lss", "leq",
  "gtr", "geq", "exist", "defined", "errorlevel", "goto", "call", "verify",
} do
  symbols[name] = "keyword"
  symbols[name:upper()] = "keyword"
end
for _, name in ipairs {
  "set", "setlocal", "endlocal", "echo", "type", "cd", "chdir", "md", "mkdir",
  "pause", "choice", "exit", "del", "rd", "rmdir", "copy", "xcopy", "move",
  "ren", "find", "findstr", "sort", "shift", "attrib", "cmd", "forfiles",
} do
  symbols[name] = "function"
  symbols[name:upper()] = "function"
end

syntax.add {
  files = { "%.bat$", "%.cmd$" },
  comment = "rem",
  patterns = {
    { pattern = "[Rr][Ee][Mm].-\n",     type = "comment" },
    { pattern = "::.-\n",               type = "comment" },
    { pattern = "%s*:[%w%-_]+",         type = "symbol" },
    { pattern = "%%%w+%%",               type = "keyword2" },
    { pattern = "%%%%?~?[%w:]+",         type = "keyword2" },
    { pattern = { '"', '"', '\\' },     type = "string" },
    { pattern = "-?%d+%.?%d*",           type = "number" },
    { pattern = "[!=()%>&%^/\\@|]",     type = "operator" },
    { pattern = "[%a_][%w_]*",           type = "symbol" },
  },
  symbols = symbols,
}
