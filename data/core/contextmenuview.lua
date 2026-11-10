local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local contextmenu = require "core.contextmenu"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"


local function vertical_padding()
  return math.floor(style.padding.y / 2)
end


local function margin()
  local size = core.root_view.size
  return math.max(0, math.min(style.contextmenu_margin or style.padding.x,
    (size.x - 1) / 2, (size.y - 1) / 2))
end


local ContextMenuView = View:extend()


function ContextMenuView:new()
  ContextMenuView.super.new(self)
  self.floating = true
  self.session = nil
  self.mouse_x, self.mouse_y = 0, 0
  self.menus = {}
end

function ContextMenuView:is_shown()
  return #self.menus > 0
end

function ContextMenuView:exit()
  self:close()
end

function ContextMenuView:close()
  if not self:is_shown() then return end
  local session = self.session
  self.menus = {}
  self.session = nil
  if core.active_view == self then
    core.set_active_view(session.target)
    -- Locked panes use last_active_view to find an editor for opened files.
    core.last_active_view = session.previous_view ~= session.target
        and session.previous_view or session.previous_last_view
  elseif core.last_active_view == self then
    core.last_active_view = session.target
  end
  core.redraw = true
end

function ContextMenuView:should_forward_mouse_press(button)
  return button == "right"
end

function ContextMenuView:on_key_pressed(key)
  keymap.on_key_pressed(key, function(name)
    return name:find("^contextmenu:") ~= nil
  end)
  -- Consume unhandled keys too: commands for layout nodes cannot run while
  -- this floating view owns focus. Keymap still tracks modifier key state.
  return true
end

function ContextMenuView:get_item_height(item)
  if item.separator then
    return style.divider_size + style.padding.y
  end
  return style.font:get_height() + style.padding.y
end

function ContextMenuView:measure(items)
  local font = style.font
  local xpad = style.padding.x * 2
  local width = style.contextmenu_min_width or math.ceil(140 * SCALE)

  for _, item in ipairs(items) do
    if not item.separator then
      local w = font:get_width(item.text)
      if item.info or item.submenu then
        local hint = item.info and item.info or ""
        if item.submenu then
          hint = hint .. (hint ~= "" and "  >" or ">")
        end
        w = w + style.padding.x * 2 + font:get_width(hint)
      end
      width = math.max(width, w + xpad)
    end
  end

  local root = core.root_view
  width = math.min(width, math.max(1, root.size.x - margin() * 2))

  local height = vertical_padding() * 2
  for _, item in ipairs(items) do
    height = height + self:get_item_height(item)
  end
  return math.floor(width), math.ceil(height)
end

function ContextMenuView:first_selectable(items)
  for i, item in ipairs(items) do
    if not item.separator and item.enabled then
      return i
    end
  end
end

function ContextMenuView:create_entry(items, x, y, parent, parent_index)
  local w, content_height = self:measure(items)
  local root = core.root_view
  local m = margin()
  local h = math.min(content_height, math.max(1, root.size.y - m * 2))
  x = common.clamp(x, m, math.max(m, root.size.x - w - m))
  y = common.clamp(y, m, math.max(m, root.size.y - h - m))
  local entry = {
    items = items,
    x = math.floor(x),
    y = math.floor(y),
    w = w,
    h = h,
    content_height = content_height,
    scroll = 0,
    selection = self:first_selectable(items),
    parent = parent,
    parent_index = parent_index,
  }
  self:ensure_selection_visible(entry)
  return entry
end

function ContextMenuView:open(target, x, y)
  if not target then return false end
  if self:is_shown() then
    self:close()
  end

  local session = {
    target = target,
    previous_view = core.active_view,
    previous_last_view = core.last_active_view,
    x = x,
    y = y,
  }
  core.set_active_view(target)
  local ok, items = core.try(function()
    target:on_context_menu(x, y)
    return contextmenu.resolve(target, x, y)
  end)
  core.active_view = session.previous_view
  core.last_active_view = session.previous_last_view
  if not ok or #items == 0 then return false end

  self.session = session
  self.mouse_x, self.mouse_y = x, y
  self.menus = { self:create_entry(items, x, y) }
  self.window_width, self.window_height = core.root_view.size.x, core.root_view.size.y
  core.set_active_view(self)
  core.redraw = true
  return true
end

function ContextMenuView:get_item_rect(entry, idx)
  local y = entry.y + self:get_entry_padding(entry) - entry.scroll
  for i = 1, idx - 1 do
    y = y + self:get_item_height(entry.items[i])
  end
  return entry.x, y, entry.w, self:get_item_height(entry.items[idx])
end

function ContextMenuView:get_entry_padding(entry)
  return math.min(vertical_padding(), math.max(0, (entry.h - 1) / 2))
end

function ContextMenuView:ensure_selection_visible(entry)
  if entry.selection then
    local _, y, _, h = self:get_item_rect(entry, entry.selection)
    local top = entry.y + self:get_entry_padding(entry)
    local bottom = entry.y + entry.h - self:get_entry_padding(entry)
    if y < top then
      entry.scroll = entry.scroll + y - top
    elseif y + h > bottom then
      entry.scroll = entry.scroll + math.min(y - top, y + h - bottom)
    end
  end
  entry.scroll = common.clamp(entry.scroll, 0,
    math.max(0, entry.content_height - entry.h))
end

function ContextMenuView:level_at(x, y)
  for i = #self.menus, 1, -1 do
    if self:entry_contains(self.menus[i], x, y) then return i end
  end
end

function ContextMenuView:trim_submenus(level)
  while #self.menus > level do
    table.remove(self.menus)
    core.redraw = true
  end
end

function ContextMenuView:entry_contains(entry, x, y)
  return x >= entry.x and x < entry.x + entry.w
      and y >= entry.y and y < entry.y + entry.h
end

function ContextMenuView:floating_contains_point(x, y)
  for _, entry in ipairs(self.menus) do
    if self:entry_contains(entry, x, y) then
      return true
    end
  end
  return false
end

function ContextMenuView:item_at(entry, x, y)
  if not self:entry_contains(entry, x, y) then return end
  local top = entry.y + self:get_entry_padding(entry)
  local bottom = entry.y + entry.h - self:get_entry_padding(entry)
  if y < top or y >= bottom then return end

  local y0 = top - entry.scroll
  for i, item in ipairs(entry.items) do
    local h = self:get_item_height(item)
    if y >= y0 and y < y0 + h then
      if item.separator then return end
      return i, item
    end
    y0 = y0 + h
  end
end

function ContextMenuView:open_submenu(entry, idx, item)
  local level
  for i, e in ipairs(self.menus) do
    if e == entry then
      level = i
      break
    end
  end
  if not level or not item.submenu then return end

  self:trim_submenus(level)

  local _, y = self:get_item_rect(entry, idx)
  local w = self:measure(item.submenu)
  local root = core.root_view
  local m = margin()

  local x = entry.x + entry.w
  if x + w > root.size.x - m then
    x = entry.x - w
  end
  table.insert(self.menus, self:create_entry(item.submenu, x, y, entry, idx))
  core.redraw = true
end

function ContextMenuView:open_selected_submenu()
  local entry = self.menus[#self.menus]
  if not entry or not entry.selection then return end
  local item = entry.items[entry.selection]
  if item and item.enabled and item.submenu then
    self:open_submenu(entry, entry.selection, item)
  end
end

function ContextMenuView:close_submenu()
  if #self.menus > 1 then
    table.remove(self.menus)
    core.redraw = true
  end
end

function ContextMenuView:move_selection(delta)
  local entry = self.menus[#self.menus]
  if not entry or #entry.items == 0 then return end

  local n = #entry.items
  local idx = entry.selection or (delta > 0 and 0 or n + 1)
  for _ = 1, n do
    idx = idx + delta
    if idx > n then
      idx = 1
    elseif idx < 1 then
      idx = n
    end
    local item = entry.items[idx]
    if not item.separator and item.enabled then
      entry.selection = idx
      self:ensure_selection_visible(entry)
      core.redraw = true
      return
    end
  end
end

function ContextMenuView:perform(item)
  local session = self.session
  self:close()
  if item.action then
    core.try(item.action, session.target, session.x, session.y, item)
  elseif item.command then
    command.perform(item.command)
  end
  core.redraw = true
end

function ContextMenuView:confirm()
  local entry = self.menus[#self.menus]
  if not entry or not entry.selection then return end
  local item = entry.items[entry.selection]
  if not item or not item.enabled then return end
  if item.submenu then
    self:open_submenu(entry, entry.selection, item)
  else
    self:perform(item)
  end
end

function ContextMenuView:on_mouse_moved(x, y)
  self.cursor = "arrow"
  self.mouse_x, self.mouse_y = x, y
  local level = self:level_at(x, y)
  if not level then return end

  -- moving back over a parent level dismisses deeper submenus
  self:trim_submenus(level)

  local entry = self.menus[level]
  local idx = self:item_at(entry, x, y)
  if idx and entry.selection ~= idx then
    entry.selection = idx
    core.redraw = true
  end
end

function ContextMenuView:on_mouse_pressed(button, x, y)
  if button ~= "left" then return end

  local level = self:level_at(x, y)
  if not level then return end

  self:trim_submenus(level)

  local entry = self.menus[level]
  local idx, item = self:item_at(entry, x, y)
  if not item then return end

  entry.selection = idx
  if not item.enabled then return end
  if item.submenu then
    self:open_submenu(entry, idx, item)
  else
    self:perform(item)
  end
end

function ContextMenuView:on_mouse_wheel(delta)
  local level = self:level_at(self.mouse_x, self.mouse_y) or #self.menus
  local entry = self.menus[level]
  if not entry then return end
  local scroll = common.clamp(entry.scroll - delta * config.mouse_wheel_scroll,
    0, math.max(0, entry.content_height - entry.h))
  if scroll ~= entry.scroll then
    entry.scroll = scroll
    self:trim_submenus(level)
    core.redraw = true
  end
end

function ContextMenuView:update()
  if not self:is_shown() then return end
  if core.active_view ~= self then
    self:close()
    return
  end
  local size = core.root_view.size
  if size.x ~= self.window_width or size.y ~= self.window_height then
    for i, old in ipairs(self.menus) do
      local parent = self.menus[i - 1]
      local x, y = old.x, old.y
      if parent then
        local w = self:measure(old.items)
        x = parent.x + parent.w
        if x + w > size.x - margin() then x = parent.x - w end
        local _, item_y = self:get_item_rect(parent, old.parent_index)
        y = item_y
      end
      local entry = self:create_entry(old.items, x, y, parent, old.parent_index)
      entry.selection, entry.scroll = old.selection, old.scroll
      self:ensure_selection_visible(entry)
      self.menus[i] = entry
    end
    self.window_width, self.window_height = size.x, size.y
    core.redraw = true
  end
end

function ContextMenuView:draw()
  local radius = style.contextmenu_corner_radius or 0
  local background = style.contextmenu_background or style.background2
  local border_color = style.contextmenu_border_color or style.divider

  -- Each panel is a full menu (the root or an open submenu), not a row.
  for _, panel in ipairs(self.menus) do
    local xpad = math.min(style.padding.x, math.max(0, (panel.w - 1) / 2))
    local border = common.clamp(style.contextmenu_border_width or style.divider_size,
      0, math.min(panel.w, panel.h) / 2)
    if border > 0 then
      common.draw_rounded_rect(panel.x, panel.y, panel.w, panel.h, radius, border_color)
    end
    if panel.w > border * 2 and panel.h > border * 2 then
      common.draw_rounded_rect(panel.x + border, panel.y + border,
        panel.w - border * 2, panel.h - border * 2,
        math.max(0, radius - border), background)
    end

    local padding = self:get_entry_padding(panel)
    local clip_padding = math.max(padding, border)
    core.push_clip_rect(panel.x + border, panel.y + clip_padding,
      panel.w - border * 2, panel.h - clip_padding * 2)

    -- Draw only the hovered/keyboard-selected row's background.
    if panel.selection then
      local x, y, w, h = self:get_item_rect(panel, panel.selection)
      if w > 4 and h > 2 then
        common.draw_rounded_rect(x + 2, y + 1, w - 4, h - 2,
          math.max(1, radius - 2), style.line_highlight)
      end
    end

    local y = panel.y + padding - panel.scroll
    for i, item in ipairs(panel.items) do
      local h = self:get_item_height(item)
      if item.separator then
        local sy = y + math.floor(h / 2)
        renderer.draw_rect(panel.x + xpad, sy, panel.w - xpad * 2,
          style.divider_size, style.divider)
      else
        local color = style.text
        if not item.enabled then
          color = style.dim
        elseif i == panel.selection then
          color = style.accent
        end

        local hint = item.info
        if item.submenu then
          hint = hint and (hint .. "  >") or ">"
        end

        local hint_w = 0
        if hint then
          hint_w = style.font:get_width(hint) + style.padding.x * 2
          common.draw_text(style.font, style.dim, hint, "right",
            panel.x + xpad, y, panel.w - xpad * 2, h)
        end

        local text_w = math.max(0, panel.w - xpad * 2 - hint_w)
        local text = common.crop_text(style.font, item.text, text_w, "...")
        common.draw_text(style.font, color, text, "left",
          panel.x + xpad, y, text_w, h)
      end
      y = y + h
    end
    core.pop_clip_rect()
  end
end

return ContextMenuView
