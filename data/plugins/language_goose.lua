
local syntax = require "core.syntax"

syntax.add {
  files = { "%.goose$" },
  comment = "//",
  patterns = {
    -- Comments
    { pattern = "//[^\n]*", type = "comment" },
    { pattern = { "/%*", "%*/" }, type = "comment" },

    -- Raw strings (triple quotes, no escapes)
    { pattern = { '"""', '"""' }, type = "string" },

    -- Strings and characters
    { pattern = { '"', '"', '\\' }, type = "string" },
    { pattern = { "'", "'", "\\" }, type = "string" },

    -- Hexadecimal floating-point numbers
    { pattern = [=[0[xX]([A-Fa-f0-9]+(\.[A-Fa-f0-9]*)?|\.[A-Fa-f0-9]+)[pP][+-]?\d+]=],
      type = "number" },

    -- Hexadecimal integers
    { pattern = [=[0[xX][A-Fa-f0-9]+]=], type = "number" },

    -- Decimal integers and floating-point numbers
    { pattern = [=[\d+(\.\d+)?([eE][+-]?\d+)?]=],
      type = "number" },

    -- Namespace separator
    { pattern = "::", type = "operator" },

    -- Function return arrow
    { pattern = "->", type = "operator" },

    -- Range operator
    { pattern = "%.%.", type = "operator" },

    -- Operators
    { pattern = [=[[+\-=/\*^%<>!~|&?:]]=],
      type = "operator" },

    -- Function calls
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*(?=\()]=],
      type = "function" },

    -- Identifiers
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*]=],
      type = "symbol" },
  },

  symbols = {
    -- Declarations
    ["import"] = "keyword",
    ["namespace"] = "keyword",
    ["struct"] = "keyword",
    ["enum"] = "keyword",
    ["type"] = "keyword",
    ["fn"] = "keyword",
    ["thread_fn"] = "keyword",
    ["export"] = "keyword",
    ["extern"] = "keyword",

    -- Variables and modifiers
    ["let"] = "keyword",
    ["var"] = "keyword",
    ["const"] = "keyword",
    ["pad"] = "keyword",
    ["reusable"] = "keyword",
    ["simd"] = "keyword",
    ["recursive"] = "keyword",

    -- Control flow
    ["if"] = "keyword",
    ["else"] = "keyword",
    ["while"] = "keyword",
    ["for"] = "keyword",
    ["in"] = "keyword",
    ["loop"] = "keyword",
    ["block"] = "keyword",
    ["guard"] = "keyword",
    ["defer"] = "keyword",
    ["match"] = "keyword",
    ["return"] = "keyword",
    ["break"] = "keyword",
    ["continue"] = "keyword",

    -- Type conversion
    ["as"] = "keyword",

    -- Contextual keywords
    ["from"] = "keyword",
    ["upto"] = "keyword",
    ["inline"] = "keyword",
    ["checkfree"] = "keyword",
    ["fields"] = "keyword",
    ["variants"] = "keyword",
    ["types"] = "keyword",

    -- Boolean type
    ["bool"] = "keyword2",

    -- Signed integers
    ["i8"] = "keyword2",
    ["i16"] = "keyword2",
    ["i32"] = "keyword2",
    ["i64"] = "keyword2",

    -- Unsigned integers
    ["u8"] = "keyword2",
    ["u16"] = "keyword2",
    ["u32"] = "keyword2",
    ["u64"] = "keyword2",

    -- Floating-point types
    ["f32"] = "keyword2",
    ["f64"] = "keyword2",

    -- Variable-length integer
    ["varint"] = "keyword2",

    -- Literals
    ["true"] = "literal",
    ["false"] = "literal",
    ["null"] = "literal",
    ["self"] = "literal",
  },
}

