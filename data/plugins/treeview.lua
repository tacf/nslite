local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local contextmenu = require "core.contextmenu"
local fileops = require "core.fileops"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local tables = require "core.utils.tables"

config.treeview_size = 200 * SCALE

local function get_depth(filename)
  local n = 0
  for sep in filename:gmatch("[\\/]") do
    n = n + 1
  end
  return n
end


local TreeView = View:extend()

function TreeView:new()
  TreeView.super.new(self)
  self.scrollable = true
  self.visible = true
  self.init_size = true
  self.cache = {}
  self.total_size = 0
end

function TreeView:get_cached(item)
  local t = self.cache[item.filename]
  if not t then
    t = {}
    t.filename = item.filename
    -- resolve against the project, not the cwd; they differ whenever nsl is
    -- launched from another directory
    t.abs_filename = system.absolute_path(core.project_path(item.filename))
    t.name = t.filename:match("[^\\/]+$")
    t.depth = get_depth(t.filename)
    t.type = item.type
    self.cache[t.filename] = t
  end
  return t
end

function TreeView:get_name()
  return "Project"
end

function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end

function TreeView:check_cache()
  -- invalidate cache's skip values if project_files has changed
  if core.project_files ~= self.last_project_files then
    for _, v in pairs(self.cache) do
      v.skip = nil
    end
    self.last_project_files = core.project_files
  end
end

function TreeView:each_item()
  return coroutine.wrap(function()
    self:check_cache()
    local count = 0
    local ox, oy = self:get_content_offset()
    local y = oy + style.padding.y
    local w = self.size.x
    local h = self:get_item_height()

    local i = 1
    while i <= #core.project_files do
      local item = core.project_files[i]
      local cached = self:get_cached(item)

      coroutine.yield(cached, ox, y, w, h)
      y = y + h
      count = count + 1
      i = i + 1

      if not cached.expanded then
        if cached.skip then
          i = cached.skip
        else
          local depth = cached.depth
          while i <= #core.project_files do
            local filename = core.project_files[i].filename
            if get_depth(filename) <= depth then break end
            i = i + 1
          end
          cached.skip = i
        end
      end
    end
    self.total_size = style.padding.y + count * h
  end)
end

function TreeView:get_scrollable_size()
  return self.total_size
end

function TreeView:get_item_at(px, py)
  for item, x, y, w, h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      return item
    end
  end
end

function TreeView:on_mouse_moved(px, py, ...)
  TreeView.super.on_mouse_moved(self, px, py, ...)
  self.hovered_item = self:get_item_at(px, py)
end

function TreeView:on_mouse_pressed(button, x, y, clicks)
  if TreeView.super.on_mouse_pressed(self, button, x, y, clicks) then
    return true -- started dragging the scrollbar
  end
  -- resolve from the click position rather than the cached hover, which goes
  -- stale as soon as the view scrolls without the mouse moving
  local item = self:get_item_at(x, y)
  self.hovered_item = item
  if not item then
    return
  elseif item.type == "dir" then
    item.expanded = not item.expanded
  else
    core.try(function()
      core.open_file(item.filename)
    end)
  end
end

function TreeView:update()
  -- update width
  if self.init_size or self.size.x < config.treeview_size then
    self.size.x = self.visible and config.treeview_size or 0
    self.init_size = false
  elseif self.size.x > config.treeview_size * 2 then
    self.size.x = self.visible and config.treeview_size * 2 or 0
    self.init_size = false
  elseif not self.visible then
    self:move_towards(self.size, "x", 0)
  end

  TreeView.super.update(self)

  -- the wheel scrolls without a mouse move, so refresh the highlight against
  -- the settled scroll position
  local mouse = core.root_view.mouse
  self.hovered_item = self:get_item_at(mouse.x, mouse.y)
end

function TreeView:get_item_icon(item, active, hovered)
  local icon = "f"
  if item.type == "dir" then
    icon = item.expanded and "D" or "d"
  end
  local color = (active or hovered) and style.accent or style.text
  return icon, style.icon_font, color
end

function TreeView:draw_item_chevron(item, active, hovered, x, y, w, h)
  if item.type == "dir" then
    local icon = item.expanded and "-" or "+"
    local color = (active or hovered) and style.accent or style.text
    common.draw_text(style.icon_font, color, icon, nil, x, y, 0, h)
  end
  return style.padding.x
end

function TreeView:draw_item_icon(item, active, hovered, x, y, w, h)
  local icon, font, color = self:get_item_icon(item, active, hovered)
  common.draw_text(font, color, icon, nil, x, y, 0, h)
  return font:get_width(icon)
end

function TreeView:draw()
  self:draw_background(style.background2)

  local spacing = style.font:get_width(" ") * 2

  local doc = core.active_view.doc
  local active_filename = doc and system.absolute_path(doc:get_filename() or "")

  local top, bottom = self.position.y, self.position.y + self.size.y

  for item, ix, y, w, h in self:each_item() do
    -- the iterator must run to completion to keep total_size right, but there
    -- is no point drawing rows outside the viewport
    if y + h >= top and y < bottom then
      -- both sides can be nil for an unresolvable path; nil == nil would mark
      -- every such item active
      local active = active_filename ~= nil
          and item.abs_filename == active_filename
      local hovered = item == self.hovered_item
      local color = active and style.accent or style.text
      local x = ix

      -- hovered item background
      if hovered then
        renderer.draw_rect(x, y, w, h, style.line_highlight)
        color = style.accent
      end

      -- icons
      x = x + item.depth * style.padding.x + style.padding.x
      x = x + self:draw_item_chevron(item, active, hovered, x, y, w, h)
      x = x + self:draw_item_icon(item, active, hovered, x, y, w, h)

      -- text
      x = x + spacing
      x = common.draw_text(style.font, color, item.name, nil, x, y, 0, h)
    end
  end

  self:draw_scrollbar()
end

-- init
local view = TreeView()
local node = core.root_view:get_active_node()
node:split("left", view, true)

-- register commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
    if view.visible then
      view.size.x = config.treeview_size
    end
  end,
})

keymap.add { ["mod+\\"] = "treeview:toggle" }


-- CommandView also takes focus. Restore the editor fallback before running a
-- file action, rather than leaving last_active_view pointing at the palette.
local function prompt(title, initial, submit, suggest)
  local previous, last = core.active_view, core.last_active_view
  local palette = core.command_view
  local function restore_focus()
    if core.active_view == previous or core.active_view == palette then
      core.set_active_view(previous)
      core.last_active_view = last
    elseif core.last_active_view == palette then
      core.last_active_view = previous
    end
  end
  palette:enter(title, function(text, item)
    restore_focus()
    core.try(submit, text, item)
  end, suggest, restore_focus)
  palette:set_text(initial, true)
end


contextmenu.add(TreeView, function(view, x, y)
  local item = view:get_item_at(x, y)
  local items = {}
  local directory = item and (item.type == "dir" and item.filename
    or item.filename:match("^(.*)[/\\][^/\\]+$")) or ""
  if item and item.type == "dir" then
    table.insert(items, {
      text = item.expanded and "Collapse" or "Expand",
      action = function()
        item.expanded = not item.expanded
        core.redraw = true
      end,
    })
  elseif item then
    table.insert(items, {
      text = "Open",
      action = function()
        core.open_file(item.filename)
      end,
    })
  end
  if item then table.insert(items, "-") end
  table.insert(items, {
    text = "New File...",
    action = function()
      prompt("New File", "", function(name)
        local filename = fileops.create(directory, name)
        if item and item.type == "dir" then item.expanded = true end
        core.open_file(filename)
      end)
    end,
  })
  if item and item.type == "file" then
    tables.insert_multiple(items, {
      text = "Rename File...",
      action = function()
        prompt("Rename File", item.filename:match("[^/\\]+$"), function(name)
          fileops.rename(item.filename, name)
        end)
      end,
    }, {
      text = "Delete File...",
      action = function()
        prompt("Delete " .. item.filename .. "? Open buffers will be kept", "Cancel",
          function(text, choice)
            if (choice and choice.text == "Delete") or text:lower() == "delete" then
              fileops.delete(item.filename)
            end
          end, function(text)
            local choices = {}
            for _, label in ipairs({ "Cancel", "Delete" }) do
              if label:lower():find(text:lower(), 1, true) then
                table.insert(choices, label)
              end
            end
            return choices
          end)
      end,
    })
  end
  if not item then return items end
  table.insert(items, "-")
  table.insert(items, {
    text = "Copy Path",
    action = function()
      system.set_clipboard(item.filename)
    end,
  })
  return items
end)


return TreeView
