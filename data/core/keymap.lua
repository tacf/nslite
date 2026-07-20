local command = require "core.command"
local keymap = {}

keymap.modkeys = {}
keymap.map = {}
keymap.reverse_map = {}

local modkey_map = {
  ["left ctrl"]   = "ctrl",
  ["right ctrl"]  = "ctrl",
  -- SDL calls the platform modifier "GUI": Command on macOS, Windows/Super elsewhere.
  -- The Command spellings are fallback aliases for backends that use that name directly.
  ["left gui"]      = "cmd",
  ["right gui"]     = "cmd",
  ["left command"]  = "cmd",
  ["right command"] = "cmd",
  ["left shift"]  = "shift",
  ["right shift"] = "shift",
  ["left alt"]    = "alt",
  ["right alt"]   = "altgr",
}

local modkeys = { "cmd", "ctrl", "alt", "altgr", "shift" }

local function key_to_stroke(k)
  local stroke = ""
  for _, mk in ipairs(modkeys) do
    if keymap.modkeys[mk] then
      stroke = stroke .. mk .. "+"
    end
  end
  return stroke .. k
end


local function resolve_mod(stroke)
  -- Default bindings use "mod" for the platform's primary shortcut modifier.
  local modifier = PLATFORM == "macOS" and "cmd" or "ctrl"
  return stroke:gsub("mod%+", modifier .. "+")
end


function keymap.add(map, overwrite)
  for stroke, cmds in pairs(map) do
    local binding = resolve_mod(stroke)
    local commands = cmds
    if type(commands) == "string" then
      commands = { commands }
    end
    if overwrite then
      keymap.map[binding] = commands
    else
      keymap.map[binding] = keymap.map[binding] or {}
      for i = #commands, 1, -1 do
        table.insert(keymap.map[binding], 1, commands[i])
      end
    end
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = binding
    end
  end
end


function keymap.get_binding(cmd)
  return keymap.reverse_map[cmd]
end


function keymap.on_key_pressed(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = true
    -- work-around for windows where `altgr` is treated as `ctrl+alt`
    if mk == "altgr" then
      keymap.modkeys["ctrl"] = false
    end
  else
    local stroke = key_to_stroke(k)
    local commands = keymap.map[stroke]
    if commands then
      for _, cmd in ipairs(commands) do
        local performed = command.perform(cmd)
        if performed then break end
      end
      return true
    end
  end
  return false
end


function keymap.on_key_released(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = false
  end
end


keymap.add {
  ["mod+shift+p"] = "core:find-command",
  ["mod+p"] = "core:find-file",
  ["mod+o"] = "core:open-file",
  ["mod+n"] = "core:new-doc",
  ["alt+return"] = "core:toggle-fullscreen",

  ["alt+shift+j"] = "root:split-left",
  ["alt+shift+l"] = "root:split-right",
  ["alt+shift+i"] = "root:split-up",
  ["alt+shift+k"] = "root:split-down",
  ["alt+j"] = "root:switch-to-left",
  ["alt+l"] = "root:switch-to-right",
  ["alt+i"] = "root:switch-to-up",
  ["alt+k"] = "root:switch-to-down",

  ["mod+w"] = "root:close",
  ["mod+tab"] = "root:switch-to-next-tab",
  ["mod+shift+tab"] = "root:switch-to-previous-tab",
  ["mod+pageup"] = "root:move-tab-left",
  ["mod+pagedown"] = "root:move-tab-right",
  ["alt+1"] = "root:switch-to-tab-1",
  ["alt+2"] = "root:switch-to-tab-2",
  ["alt+3"] = "root:switch-to-tab-3",
  ["alt+4"] = "root:switch-to-tab-4",
  ["alt+5"] = "root:switch-to-tab-5",
  ["alt+6"] = "root:switch-to-tab-6",
  ["alt+7"] = "root:switch-to-tab-7",
  ["alt+8"] = "root:switch-to-tab-8",
  ["alt+9"] = "root:switch-to-tab-9",

  ["mod+f"] = "find-replace:find",
  ["mod+r"] = "find-replace:replace",
  ["f3"] = { "find:next", "find-replace:repeat-find" },
  ["shift+f3"] = { "find:previous", "find-replace:previous-find" },
  ["mod+g"] = "doc:go-to-line",
  ["mod+s"] = "doc:save",
  ["mod+shift+s"] = "doc:save-as",

  ["mod+z"] = { "find:undo", "doc:undo" },
  ["mod+y"] = { "find:redo", "doc:redo" },
  ["mod+x"] = { "find:cut", "doc:cut" },
  ["mod+c"] = { "find:copy", "doc:copy" },
  ["mod+v"] = { "find:paste", "doc:paste" },
  ["escape"] = { "find:escape", "command:escape", "doc:select-none" },
  ["tab"] = { "command:complete", "doc:indent" },
  ["shift+tab"] = "doc:unindent",
  ["backspace"] = { "find:backspace", "doc:backspace" },
  ["shift+backspace"] = { "find:backspace", "doc:backspace" },
  ["mod+backspace"] = { "find:delete-word-left", "doc:delete-to-previous-word-start" },
  ["mod+shift+backspace"] = { "find:delete-word-left", "doc:delete-to-previous-word-start" },
  ["delete"] = { "find:delete", "doc:delete" },
  ["shift+delete"] = { "find:delete", "doc:delete" },
  ["mod+delete"] = { "find:delete-word-right", "doc:delete-to-next-word-end" },
  ["mod+shift+delete"] = { "find:delete-word-right", "doc:delete-to-next-word-end" },
  ["return"] = { "find:next", "command:submit", "doc:newline" },
  ["shift+return"] = "find:previous",
  ["keypad enter"] = { "find:next", "command:submit", "doc:newline" },
  ["shift+keypad enter"] = "find:previous",
  ["mod+return"] = "doc:newline-below",
  ["mod+shift+return"] = "doc:newline-above",
  ["mod+j"] = "doc:join-lines",
  ["mod+a"] = { "find:select-all", "doc:select-all" },
  ["mod+d"] = { "find-replace:select-next", "doc:select-word" },
  ["mod+l"] = "doc:select-lines",
  ["mod+/"] = "doc:toggle-line-comments",
  ["mod+up"] = "doc:move-lines-up",
  ["mod+down"] = "doc:move-lines-down",
  ["mod+shift+d"] = "doc:duplicate-lines",
  ["mod+shift+k"] = "doc:delete-lines",

  ["left"] = { "find:move-left", "doc:move-to-previous-char" },
  ["right"] = { "find:move-right", "doc:move-to-next-char" },
  ["up"] = { "command:select-previous", "doc:move-to-previous-line" },
  ["down"] = { "command:select-next", "doc:move-to-next-line" },
  ["mod+left"] = { "find:move-word-left", "doc:move-to-previous-word-start" },
  ["mod+right"] = { "find:move-word-right", "doc:move-to-next-word-end" },
  ["mod+["] = "doc:move-to-previous-block-start",
  ["mod+]"] = "doc:move-to-next-block-end",
  ["home"] = { "find:move-home", "doc:move-to-start-of-line" },
  ["end"] = { "find:move-end", "doc:move-to-end-of-line" },
  ["mod+home"] = "doc:move-to-start-of-doc",
  ["mod+end"] = "doc:move-to-end-of-doc",
  ["pageup"] = "doc:move-to-previous-page",
  ["pagedown"] = "doc:move-to-next-page",

  ["shift+left"] = { "find:select-left", "doc:select-to-previous-char" },
  ["shift+right"] = { "find:select-right", "doc:select-to-next-char" },
  ["shift+up"] = "doc:select-to-previous-line",
  ["shift+down"] = "doc:select-to-next-line",
  ["mod+shift+left"] = { "find:select-word-left", "doc:select-to-previous-word-start" },
  ["mod+shift+right"] = { "find:select-word-right", "doc:select-to-next-word-end" },
  ["mod+shift+["] = "doc:select-to-previous-block-start",
  ["mod+shift+]"] = "doc:select-to-next-block-end",
  ["shift+home"] = { "find:select-home", "doc:select-to-start-of-line" },
  ["shift+end"] = { "find:select-end", "doc:select-to-end-of-line" },
  ["mod+shift+home"] = "doc:select-to-start-of-doc",
  ["mod+shift+end"] = "doc:select-to-end-of-doc",
  ["shift+pageup"] = "doc:select-to-previous-page",
  ["shift+pagedown"] = "doc:select-to-next-page",
}

return keymap
