local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local LogView = require "core.presentations.log"
local TitleBarView = require "core.presentations.titlebar"
local renderer = require "renderer"


local fullscreen = false
local debug_enabled = false

command.add(nil, {
  ["core:quit"] = function()
    core.quit()
  end,

  ["core:force-quit"] = function()
    core.quit(true)
  end,

  ["core:toggle-fullscreen"] = function()
    fullscreen = not fullscreen
    system.set_window_mode(fullscreen and "fullscreen" or "normal")
  end,

  ["core:reload-module"] = function()
    core.command_view:enter("Reload Module", function(text, item)
      local text = item and item.text or text
      core.reload_module(text)
      core.log("Reloaded module %q", text)
    end, function(text)
      local items = {}
      for name in pairs(package.loaded) do
        table.insert(items, name)
      end
      return common.fuzzy_match(items, text)
    end)
  end,

  ["core:find-command"] = function()
    local commands = command.get_all_valid()
    core.command_view:enter("Do Command", function(text, item)
      if item then
        command.perform(item.command)
      end
    end, function(text)
      local res = common.fuzzy_match(commands, text)
      for i, name in ipairs(res) do
        res[i] = {
          text = command.prettify_name(name),
          info = keymap.get_binding(name),
          command = name,
        }
      end
      return res
    end)
  end,

  ["core:find-file"] = function()
    core.command_view:enter("Open File From Project", function(text, item)
      text = item and item.text or text
      core.open_file(text)
    end, function(text)
      local files = {}
      for _, item in pairs(core.project_files) do
        if item.type == "file" then
          table.insert(files, item.filename)
        end
      end
      return common.fuzzy_match(files, text)
    end)
  end,

  ["core:new-doc"] = function()
    core.root_view:open_doc(core.open_doc())
  end,

  ["core:open-file"] = function()
    core.command_view:enter("Open File", function(text)
      core.open_file(text)
    end, common.path_suggest)
  end,

  ["core:open-log"] = function()
    local node = core.root_view:get_active_node()
    node:add_view(LogView())
  end,

  ["core:open-user-module"] = function()
    core.open_file(USERDIR .. PATHSEP .. "init.lua")
  end,

  ["core:toggle-debug"] = function()
    debug_enabled = not debug_enabled
    renderer.show_debug(debug_enabled)
  end,

  ["core:open-project-module"] = function()
    local filename = core.project_path(".nslite_project.lua")
    if system.get_file_info(filename) then
      core.open_file(filename)
    else
      local doc = core.open_doc()
      core.root_view:open_doc(doc)
      doc:save(filename)
    end
  end,

  ["core:toggle-native-titlebar"] = function()
    config.native_title_bar = not config.native_title_bar
    if config.native_title_bar then
      system.configure_titlebar(0, 0)
      core.root_view.titlebar = nil
    else
      local th = style.font:get_height() + style.padding.y * 2
      local bm = 30 * 3 + style.padding.x
      system.configure_titlebar(th, bm)
      core.root_view.titlebar = TitleBarView()
      core.root_view.titlebar:set_title(core.window_title or "nslite")
    end
    core.redraw = true
  end,
})
