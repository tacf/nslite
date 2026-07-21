local syntax = require "core.syntax"

syntax.add {
  files = { "%.xml$", "%.html?$" },
  headers = "<%?xml",
  patterns = {
    { pattern = { "<!--", "-->" },         type = "comment"  },
    { pattern = { [=[(?<=>)[^<]]=], [=[(?<!<)(?=<)]=] }, type = "normal" },
    { pattern = { '"', '"', '\\' },        type = "string"   },
    { pattern = { "'", "'", '\\' },        type = "string"   },
    { pattern = [=[0x[\da-fA-F]+]=],       type = "number"   },
    { pattern = [=[-?\d+[\d.]*f?]=],      type = "number"   },
    { pattern = [=[-?\.?\d+f?]=],         type = "number"   },
    { pattern = [=[(?<=<)![A-Za-z_][A-Za-z0-9_]*]=], type = "keyword2" },
    { pattern = [=[(?<=<)[A-Za-z_][A-Za-z0-9_]*]=], type = "function" },
    { pattern = [=[(?<=<)/[A-Za-z_][A-Za-z0-9_]*]=], type = "function" },
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*]=], type = "keyword" },
    { pattern = "[/<>=]",                  type = "operator" },
  },
  symbols = {},
}
