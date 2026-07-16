local common = {}


function common.is_utf8_cont(char)
  local byte = char:byte()
  return byte >= 0x80 and byte < 0xc0
end


function common.utf8_chars(text)
  return text:gmatch("[\0-\x7f\xc2-\xf4][\x80-\xbf]*")
end


function common.clamp(n, lo, hi)
  return math.max(math.min(n, hi), lo)
end


function common.round(n)
  return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end


function common.lerp(a, b, t)
  if type(a) ~= "table" then
    return a + (b - a) * t
  end
  local res = {}
  for k, v in pairs(b) do
    res[k] = common.lerp(a[k], v, t)
  end
  return res
end


function common.color(str)
  local r, g, b, a = str:match("#(%x%x)(%x%x)(%x%x)")
  if r then
    r = tonumber(r, 16)
    g = tonumber(g, 16)
    b = tonumber(b, 16)
    a = 1
  elseif str:match("rgba?%s*%([%d%s%.,]+%)") then
    local f = str:gmatch("[%d.]+")
    r = (f() or 0)
    g = (f() or 0)
    b = (f() or 0)
    a = f() or 1
  else
    error(string.format("bad color string '%s'", str))
  end
  return r, g, b, a * 0xff
end


local function compare_score(a, b)
  return a.score > b.score
end

local function fuzzy_match_items(items, needle)
  local res = {}
  for _, item in ipairs(items) do
    local score = system.fuzzy_match(tostring(item), needle)
    if score then
      table.insert(res, { text = item, score = score })
    end
  end
  table.sort(res, compare_score)
  for i, item in ipairs(res) do
    res[i] = item.text
  end
  return res
end


function common.fuzzy_match(haystack, needle)
  if type(haystack) == "table" then
    return fuzzy_match_items(haystack, needle)
  end
  return system.fuzzy_match(haystack, needle)
end


function common.path_suggest(text)
  local path, name = text:match("^(.-)([^/\\]*)$")
  local files = system.list_dir(path == "" and "." or path) or {}
  local res = {}
  for _, fname in ipairs(files) do
    local file = path .. fname
    local info = system.get_file_info(file)
    if info then
      if info.type == "dir" then
        file = file .. PATHSEP
      end
      if file:lower():find(text:lower(), nil, true) == 1 then
        table.insert(res, file)
      end
    end
  end
  return res
end


function common.match_pattern(text, pattern, ...)
  if type(pattern) == "string" then
    return text:find(pattern, ...)
  end
  for _, p in ipairs(pattern) do
    local s, e = common.match_pattern(text, p, ...)
    if s then return s, e end
  end
  return false
end


-- Draws a filled rectangle with (optionally) rounded corners, emulated with
-- per-scanline horizontal spans since the renderer only fills plain rects.
-- `corners` is an optional table { tl, tr, bl, br } of booleans (default: all).
function common.draw_rounded_rect(x, y, w, h, radius, color, corners)
  radius = math.min(radius or 0, math.floor(w / 2), math.floor(h / 2))
  if radius <= 0 then
    renderer.draw_rect(x, y, w, h, color)
    return
  end
  corners = corners or { tl = true, tr = true, bl = true, br = true }

  -- straight middle band spanning the full width
  renderer.draw_rect(x, y + radius, w, h - radius * 2, color)

  for i = 0, radius - 1 do
    local dy = radius - i - 0.5
    local chord = math.sqrt(math.max(0, radius * radius - dy * dy))
    local inset = common.round(radius - chord)
    -- top band
    local tl = corners.tl and inset or 0
    local tr = corners.tr and inset or 0
    renderer.draw_rect(x + tl, y + i, w - tl - tr, 1, color)
    -- bottom band
    local bl = corners.bl and inset or 0
    local br = corners.br and inset or 0
    renderer.draw_rect(x + bl, y + h - 1 - i, w - bl - br, 1, color)
  end
end


function common.draw_text(font, color, text, align, x,y,w,h)
  local tw, th = font:get_width(text), font:get_height(text)
  if align == "center" then
    x = x + (w - tw) / 2
  elseif align == "right" then
    x = x + (w - tw)
  end
  y = common.round(y + (h - th) / 2)
  return renderer.draw_text(font, text, x, y, color), y + th
end


function common.bench(name, fn, ...)
  local start = system.get_time()
  local res = fn(...)
  local t = system.get_time() - start
  local ms = t * 1000
  local per = (t / (1 / 60)) * 100
  print(string.format("*** %-16s : %8.3fms %6.2f%%", name, ms, per))
  return res
end


return common
