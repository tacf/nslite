local common = require "core.common"
local document = require "document"

local syntax = {}
syntax.items = {}

-- Token patterns are PCRE2 expressions compiled by the native Document API.
local plain_text_syntax = { patterns = {}, symbols = {} }
plain_text_syntax.native = document.compile_syntax(plain_text_syntax)


function syntax.add(t)
  t.native = document.compile_syntax(t)
  table.insert(syntax.items, t)
end


local function find(string, field)
  for i = #syntax.items, 1, -1 do
    local t = syntax.items[i]
    if common.match_pattern(string, t[field] or {}) then
      return t
    end
  end
end

function syntax.get(filename, header)
  return find(filename, "files")
      or find(header, "headers")
      or plain_text_syntax
end


return syntax
