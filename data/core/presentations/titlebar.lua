local core = require "core"
local common = require "core.common"
local style = require "core.style"
local View = require "core.view"


local TitleBarView = View:extend()

local BUTTON_SIZE = 30
local ICON_PADDING = 8
local ICON_SIZE = 30

local app_icon = nil


function TitleBarView:new()
  TitleBarView.super.new(self)
  self.title = ""
  self.maximized = false
  self.hovered_button = nil
  self.pressed_button = nil
end

function TitleBarView:set_title(title)
  self.title = title
end

function TitleBarView:get_button_rect(index)
  local x = self.position.x + self.size.x - (BUTTON_SIZE * (4 - index))
  local y = self.position.y
  return x, y, BUTTON_SIZE, self.size.y
end

function TitleBarView:get_button_at(x, y)
  for i = 1, 3 do
    local bx, by, bw, bh = self:get_button_rect(i)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      return i
    end
  end
  return nil
end

function TitleBarView:on_mouse_pressed(button, x, y, clicks)
  if button ~= "left" then return end
  local btn = self:get_button_at(x, y)
  if btn then
    self.pressed_button = btn
    return true
  end
  return false
end

function TitleBarView:on_mouse_released(button, x, y)
  if button ~= "left" then return end
  if self.pressed_button then
    local btn = self:get_button_at(x, y)
    if btn == self.pressed_button then
      if btn == 1 then
        system.minimize_window()
      elseif btn == 2 then
        self:toggle_maximize()
      elseif btn == 3 then
        core.quit()
      end
    end
    self.pressed_button = nil
    return true
  end
  return false
end

function TitleBarView:on_mouse_moved(x, y, dx, dy)
  local btn = self:get_button_at(x, y)
  if btn ~= self.hovered_button then
    self.hovered_button = btn
    core.redraw = true
  end
  return false
end

function TitleBarView:toggle_maximize()
  if self.maximized then
    system.set_window_mode("normal")
  else
    system.set_window_mode("maximized")
  end
  self.maximized = not self.maximized
end

function TitleBarView:update()
  self.size.y = style.font:get_height() + style.padding.y * 2
  self.cursor = "arrow"
  if self.hovered_button then
    self.cursor = "hand"
  end
  TitleBarView.super.update(self)
end

function TitleBarView:draw()
  local h = self.size.y
  local x = self.position.x
  local y = self.position.y
  local w = self.size.x

  self:draw_background(style.background2)

  -- divider at bottom
  local ds = style.divider_size
  renderer.draw_rect(x, y + h - ds, w, ds, style.divider)

  -- icon
  if not app_icon and WINDOW_ICON then
    app_icon = WINDOW_ICON
  end
  if app_icon then
    local icon_x = x + style.padding.x
    local icon_y = y + math.floor((h - ICON_SIZE) / 2)
    renderer.draw_image(app_icon, icon_x, icon_y, ICON_SIZE, ICON_SIZE)
  end

  -- title text
  local title_x = x + style.padding.x * 2 + ICON_SIZE + ICON_PADDING
  local buttons_area = BUTTON_SIZE * 3
  local title_w = math.max(0, w - (title_x - x) - buttons_area - style.padding.x)
  local label, cropped = common.crop_text(style.font, self.title, title_w, "...")
  common.draw_text(style.font, style.text, label,
    cropped and "left" or "center", title_x, y, title_w, h)

  -- window control buttons
  local button_labels = { "-", "^", "x" }

  for i = 1, 3 do
    local bx, by, bw, bh = self:get_button_rect(i)
    local is_hovered = self.hovered_button == i
    local is_pressed = self.pressed_button == i

    local color = style.dim
    if is_hovered then
      color = style.accent
    end
    if is_pressed then
      color = style.text
    end
    common.draw_text(style.icon_font, color, button_labels[i], "center", bx, by, bw, bh)
  end
end

return TitleBarView
