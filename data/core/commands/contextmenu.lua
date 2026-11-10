local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"


command.add(function()
  return core.context_menu ~= nil and core.context_menu:is_shown()
end, {
  ["contextmenu:select-previous"] = function()
    core.context_menu:move_selection(-1)
  end,
  ["contextmenu:select-next"] = function()
    core.context_menu:move_selection(1)
  end,
  ["contextmenu:open-submenu"] = function()
    core.context_menu:open_selected_submenu()
  end,
  ["contextmenu:close-submenu"] = function()
    core.context_menu:close_submenu()
  end,
  ["contextmenu:confirm"] = function()
    core.context_menu:confirm()
  end,
  ["contextmenu:close"] = function()
    core.context_menu:close()
  end,
})

keymap.add {
  ["up"] = "contextmenu:select-previous",
  ["down"] = "contextmenu:select-next",
  ["left"] = "contextmenu:close-submenu",
  ["right"] = "contextmenu:open-submenu",
  ["return"] = "contextmenu:confirm",
  ["keypad enter"] = "contextmenu:confirm",
  ["escape"] = "contextmenu:close",
}
