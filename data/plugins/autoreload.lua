local core = require "core"
local config = require "core.config"
local Doc = require "core.doc"


local times = setmetatable({}, { __mode = "k" })

local function update_time(doc)
  local info = system.get_file_info(doc:get_filename())
  times[doc] = info.modified
end


local function reload_doc(doc)
  local sel = { doc:get_selection() }
  local filename = doc:get_filename()
  doc:load(filename)
  doc:set_selection(table.unpack(sel))

  core.log_quiet("Auto-reloaded doc \"%s\"", filename)
end


core.add_thread(function()
  while true do
    -- check all doc modified times
    for _, doc in ipairs(core.docs) do
      local info = system.get_file_info(doc:get_filename() or "")
      if info and times[doc] ~= info.modified then
        reload_doc(doc)
      end
      coroutine.yield()
    end

    -- wait for next scan
    coroutine.yield(config.project_scan_rate)
  end
end)


-- patch `Doc.save|load` to store modified time
local load = Doc.load
local save = Doc.save

Doc.load = function(self, ...)
  local res = load(self, ...)
  update_time(self)
  return res
end

Doc.save = function(self, ...)
  local res = save(self, ...)
  update_time(self)
  return res
end
