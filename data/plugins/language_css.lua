local syntax = require "core.syntax"

syntax.add {
  files = { "%.css$" },
  patterns = {
    { pattern = [=[\\.]=],            type = "normal"   },
    { pattern = [=[//.*?\n]=],        type = "comment"  },
    { pattern = { [=[/\*]=], [=[\*/]=] }, type = "comment" },
    { pattern = { '"', '"', '\\' },   type = "string"   },
    { pattern = { "'", "'", '\\' },   type = "string"   },
    { pattern = [=[[A-Za-z][A-Za-z0-9-]*\s*(?=:)]=], type = "keyword" },
    { pattern = [=[#[A-Fa-f0-9]+]=],  type = "string"   },
    { pattern = [=[-?\d+[\d.]*p[xt]]=], type = "number" },
    { pattern = [=[-?\d+[\d.]*deg]=], type = "number" },
    { pattern = [=[-?\d+[\d.]*]=],  type = "number"   },
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*]=], type = "symbol" },
    { pattern = [=[#[A-Za-z][A-Za-z0-9_-]*]=], type = "keyword2" },
    { pattern = [=[@[A-Za-z][A-Za-z0-9_-]*]=], type = "keyword2" },
    { pattern = [=[\.[A-Za-z][A-Za-z0-9_-]*]=], type = "keyword2" },
    { pattern = "[{}:]",              type = "operator" },
  },
  symbols = {},
}
