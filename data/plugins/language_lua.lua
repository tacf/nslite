local syntax = require "core.syntax"

syntax.add {
  files = "%.lua$",
  headers = "^#!.*[ /]lua",
  comment = "--",

  patterns = {
    -- Quoted strings
    { pattern = { '"', '"', '\\' },               type = "string" },
    { pattern = { "'", "'", '\\' },               type = "string" },

    -- Multiline comments (long brackets)
    { pattern = { [=[--\[==\[]=], [=[\]==\]]=] }, type = "comment" },
    { pattern = { [=[--\[=\[]=], [=[\]=\]]=] },   type = "comment" },
    { pattern = { [=[--\[\[]=], [=[\]\]]=] },     type = "comment" },

    -- Single-line comments
    { pattern = [=[--[^\r\n]*]=],                 type = "comment" },

    -- Multiline strings (long brackets)
    { pattern = { [=[\[==\[]=], [=[\]==\]]=] },   type = "string" },
    { pattern = { [=[\[=\[]=], [=[\]=\]]=] },     type = "string" },
    { pattern = { [=[\[\[]=], [=[\]\]]=] },       type = "string" },

    -- Hexadecimal numbers
    { pattern = [=[0[xX](?:[0-9A-Fa-f]+(?:\.(?!\.)[0-9A-Fa-f]*)?|\.[0-9A-Fa-f]+)(?:[pP][+-]?\d+)?]=],
      type = "number" },

    -- Decimal numbers, including scientific notation
    { pattern = [=[(?:\d+\.(?!\.)\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?]=],
      type = "number" },

    -- Special keywords
    { pattern = [=[<[A-Za-z]+>]=], type = "keyword2" },

    -- Lua labels
    { pattern = [=[::[A-Za-z_][A-Za-z0-9_]*::]=],
      type = "function" },

    -- Range / concatenation operators
    { pattern = [=[\.\.\.?]=],     type = "operator" },

    -- Multi-character operators
    { pattern = [=[<=|>=|==|~=|//|<<|>>]=],
      type = "operator" },

    -- Single-character operators
    { pattern = [=[[+\-=/\*^%#<>&|~]]=],
      type = "operator" },

    -- Function calls
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*(?=\s*[("{])]=],
      type = "function" },

    -- Identifiers
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*]=],
      type = "symbol" },
  },
  symbols = {
    ["if"]       = "keyword",
    ["then"]     = "keyword",
    ["else"]     = "keyword",
    ["elseif"]   = "keyword",
    ["end"]      = "keyword",
    ["do"]       = "keyword",
    ["function"] = "keyword",
    ["repeat"]   = "keyword",
    ["until"]    = "keyword",
    ["while"]    = "keyword",
    ["for"]      = "keyword",
    ["break"]    = "keyword",
    ["return"]   = "keyword",
    ["local"]    = "keyword",
    ["in"]       = "keyword",
    ["not"]      = "keyword",
    ["and"]      = "keyword",
    ["or"]       = "keyword",
    ["goto"]     = "keyword",
    ["self"]     = "keyword2",
    ["true"]     = "literal",
    ["false"]    = "literal",
    ["nil"]      = "literal",
  },
}
