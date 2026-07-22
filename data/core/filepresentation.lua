local core = require "core"
local DocView = require "core.docview"


local filepresentation = { items = {} }


local function matches(filename, patterns)
  for _, pattern in ipairs(patterns) do
    if filename:find(pattern) then return true end
  end
  return false
end


-- Register a specialized way to present a file. Later registrations take
-- priority, allowing plugins or user configuration to override built-ins.
function filepresentation.add(item)
  assert(type(item) == "table", "expected a file presentation")
  assert(type(item.files) == "table", "expected file patterns")
  assert(type(item.open) == "function", "expected an open function")
  table.insert(filepresentation.items, 1, item)
end

function filepresentation.open(filename)
  local item = filepresentation.resolve(filename)
  if item then return item.open(filename) end

  -- flow fallsback to default DocView presentation
  return filepresentation.open_document(filename)
end

function filepresentation.resolve(filename)
  local normalized = (filename or ""):lower()
  for _, item in ipairs(filepresentation.items) do
    if matches(normalized, item.files) then return item end
  end
end

-- Default file presentation DocView
function filepresentation.open_document(filename, ViewType)
  local doc = core.open_doc(filename)
  return core.root_view:open_doc(doc, ViewType or DocView)
end

filepresentation.add {
  name = "image",
  files = {
    "%.png$", "%.jpe?g$", "%.jfif$", "%.bmp$", "%.gif$", "%.webp$",
    "%.svg$", "%.tga$", "%.qoi$", "%.ico$", "%.pnm$", "%.ppm$",
    "%.pgm$", "%.pbm$",
  },
  open = function(filename)
    local ImageView = require "core.presentations.image"
    local absolute_filename = system.absolute_path(filename)
    local view = ImageView(absolute_filename)
    return core.root_view:open_view(view, function(existing)
      return existing:is(ImageView)
          and system.absolute_path(existing.filename) == absolute_filename
    end)
  end,
}

filepresentation.add {
  name = "font",
  files = { "%.ttf$", "%.otf$" },
  open = function(filename)
    local FontView = require "core.presentations.font"
    local absolute_filename = system.absolute_path(filename)
    local view = FontView(absolute_filename)
    return core.root_view:open_view(view, function(existing)
      return existing:is(FontView)
          and system.absolute_path(existing.filename) == absolute_filename
    end)
  end,
}

return filepresentation
