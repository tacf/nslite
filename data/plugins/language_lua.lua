local syntax = require "core.syntax"

syntax.add {
  files = "%.lua$",
  headers = "^#!.*[ /]lua",
  comment = "--",

patterns = {
  -- Quoted strings
  { pattern = { '"', '"', '\\' }, type = "string" },
  { pattern = { "'", "'", '\\' }, type = "string" },

  -- Multiline comments (long brackets)
  { regex = { [=[--\[==\[]=], [=[\]==\]]=] }, type = "comment" },
  { regex = { [=[--\[=\[]=],  [=[\]=\]]=] },  type = "comment" },
  { regex = { [=[--\[\[]=],   [=[\]\]]=] },   type = "comment" },

  -- Single-line comments
  { regex = [=[--[^\r\n]*]=], type = "comment" },

  -- Multiline strings (long brackets)
  { regex = { [=[\[==\[]=], [=[\]==\]]=] }, type = "string" },
  { regex = { [=[\[=\[]=],  [=[\]=\]]=] },  type = "string" },
  { regex = { [=[\[\[]=],   [=[\]\]]=] },   type = "string" },

  -- Hexadecimal numbers
  { regex = [=[0[xX](?:[0-9A-Fa-f]+(?:\.(?!\.)[0-9A-Fa-f]*)?|\.[0-9A-Fa-f]+)(?:[pP][+-]?\d+)?]=],
    type = "number" },

  -- Decimal numbers, including scientific notation
  { regex = [=[(?:\d+\.(?!\.)\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?]=],
    type = "number" },

  -- Special keywords
  { regex = [=[<[A-Za-z]+>]=], type = "keyword2" },

  -- Lua labels
  { regex = [=[::[A-Za-z_][A-Za-z0-9_]*::]=],
    type = "function" },

  -- Range / concatenation operators
  { regex = [=[\.\.\.?]=], type = "operator" },

  -- Multi-character operators
  { regex = [=[<=|>=|==|~=|//|<<|>>]=],
    type = "operator" },

  -- Single-character operators
  { regex = [=[[+\-=/\*^%#<>&|~]]=],
    type = "operator" },

  -- Function calls
  { regex = [=[[A-Za-z_][A-Za-z0-9_]*(?=\s*[("{])]=],
    type = "function" },

  -- Identifiers
  { regex = [=[[A-Za-z_][A-Za-z0-9_]*]=],
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
