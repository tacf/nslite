local core = require "core"
local common = require "core.common"
local style = require "core.style"
local View = require "core.view"


local ImageView = View:extend()

local MIN_ZOOM = 0.01
local MAX_ZOOM = 32
local ZOOM_FACTOR = 1.25
local BUTTON_SIZE = 32 * SCALE
local LABEL_WIDTH = 62 * SCALE
local CONTROL_GAP = 6 * SCALE
local CONTROL_MARGIN = 12 * SCALE

local IMAGE_TYPES = {
  jpg = "JPEG",
  jpeg = "JPEG",
  jfif = "JPEG",
}


local function contains(rect, x, y)
  return x >= rect.x and x < rect.x + rect.width
      and y >= rect.y and y < rect.y + rect.height
end


local function get_image_type(filename)
  local extension = filename:match("%.([^./\\]+)$")
  if not extension then return "IMAGE" end
  extension = extension:lower()
  return IMAGE_TYPES[extension] or extension:upper()
end


function ImageView:new(filename)
  ImageView.super.new(self)
  self.filename = filename
  self.image = renderer.image.load(filename)
  self.image_width = self.image:get_width()
  self.image_height = self.image:get_height()
  self.image_type = get_image_type(filename)
  local file_info = system.get_file_info(filename)
  self.file_size = file_info and file_info.size or 0
  self.zoom = 1
  self.minimum_zoom = MIN_ZOOM
  self.pan = { x = 0, y = 0 }
end


function ImageView:get_name()
  return self.filename:match("[^/\\]+$") or self.filename
end


function ImageView:get_scaled_size()
  return math.max(1, common.round(self.image_width * self.zoom)),
    math.max(1, common.round(self.image_height * self.zoom))
end


function ImageView:get_image_position()
  local width, height = self:get_scaled_size()
  return self.position.x + (self.size.x - width) / 2 + self.pan.x,
    self.position.y + (self.size.y - height) / 2 + self.pan.y,
    width, height
end


function ImageView:clamp_pan()
  local width, height = self:get_scaled_size()
  local overflow_x = math.max(0, (width - self.size.x) / 2)
  local overflow_y = math.max(0, (height - self.size.y) / 2)
  self.pan.x = common.clamp(self.pan.x, -overflow_x, overflow_x)
  self.pan.y = common.clamp(self.pan.y, -overflow_y, overflow_y)
end


function ImageView:image_overflows()
  local width, height = self:get_scaled_size()
  return width > self.size.x or height > self.size.y
end


function ImageView:initialize_zoom()
  if self.zoom_initialized or self.size.x <= 0 or self.size.y <= 0 then return end
  local fit = math.min(1, self.size.x / self.image_width,
    self.size.y / self.image_height)
  self.zoom = fit
  self.minimum_zoom = math.min(MIN_ZOOM, fit)
  self.zoom_initialized = true
  core.redraw = true
end


function ImageView:set_zoom(zoom, anchor_x, anchor_y)
  self:initialize_zoom()
  zoom = common.clamp(zoom, self.minimum_zoom, MAX_ZOOM)
  if zoom == self.zoom then return end

  anchor_x = anchor_x or self.position.x + self.size.x / 2
  anchor_y = anchor_y or self.position.y + self.size.y / 2

  local image_x, image_y, width, height = self:get_image_position()
  local relative_x = (anchor_x - image_x) / width
  local relative_y = (anchor_y - image_y) / height

  self.zoom = zoom
  local new_width, new_height = self:get_scaled_size()
  local centered_x = self.position.x + (self.size.x - new_width) / 2
  local centered_y = self.position.y + (self.size.y - new_height) / 2
  self.pan.x = anchor_x - centered_x - relative_x * new_width
  self.pan.y = anchor_y - centered_y - relative_y * new_height
  self:clamp_pan()
  core.redraw = true
end


function ImageView:zoom_by(steps, anchor_x, anchor_y)
  self:set_zoom(self.zoom * ZOOM_FACTOR ^ steps, anchor_x, anchor_y)
end


function ImageView:get_control_rects()
  local y = self.position.y + self.size.y - CONTROL_MARGIN - BUTTON_SIZE
  local plus = {
    x = self.position.x + self.size.x - CONTROL_MARGIN - BUTTON_SIZE,
    y = y, width = BUTTON_SIZE, height = BUTTON_SIZE,
  }
  local label = {
    x = plus.x - CONTROL_GAP - LABEL_WIDTH,
    y = y, width = LABEL_WIDTH, height = BUTTON_SIZE,
  }
  local minus = {
    x = label.x - CONTROL_GAP - BUTTON_SIZE,
    y = y, width = BUTTON_SIZE, height = BUTTON_SIZE,
  }
  return minus, label, plus
end


function ImageView:on_mouse_pressed(button, x, y)
  if button ~= "left" then return end

  local minus, label, plus = self:get_control_rects()
  if contains(minus, x, y) then
    self:zoom_by(-1)
    return true
  elseif contains(plus, x, y) then
    self:zoom_by(1)
    return true
  elseif contains(label, x, y) then
    return true
  elseif self:image_overflows() then
    self.dragging_image = true
    self.cursor = "hand"
    return true
  end
end


function ImageView:on_mouse_released(button)
  if button == "left" then self.dragging_image = false end
end


function ImageView:on_mouse_moved(x, y, dx, dy)
  local minus, label, plus = self:get_control_rects()
  self.hovered_control = contains(minus, x, y) and "minus"
    or contains(plus, x, y) and "plus" or nil
  local over_label = contains(label, x, y)

  if self.dragging_image then
    self.pan.x = self.pan.x + dx
    self.pan.y = self.pan.y + dy
    self:clamp_pan()
    core.redraw = true
  end

  self.cursor = self.hovered_control and "hand"
    or (not over_label and self:image_overflows()) and "hand" or "arrow"
end


function ImageView:on_mouse_wheel(delta)
  local mouse = core.root_view.mouse
  self:zoom_by(delta, mouse and mouse.x, mouse and mouse.y)
end


function ImageView:update()
  self:initialize_zoom()
  self:clamp_pan()
end


local function draw_button(rect, text, hovered)
  local color = hovered and style.line_highlight or style.background3
  renderer.draw_rect(rect.x, rect.y, rect.width, rect.height, color)
  common.draw_text(style.big_font, style.text, text, "center",
    rect.x, rect.y, rect.width, rect.height)
end


function ImageView:draw()
  self:initialize_zoom()
  self:draw_background(style.background)

  core.push_clip_rect(self.position.x, self.position.y, self.size.x, self.size.y)
  local x, y, width, height = self:get_image_position()
  renderer.draw_image(self.image, common.round(x), common.round(y), width, height)

  local minus, label, plus = self:get_control_rects()
  draw_button(minus, "-", self.hovered_control == "minus")
  draw_button(plus, "+", self.hovered_control == "plus")
  renderer.draw_rect(label.x, label.y, label.width, label.height,
    style.background2)
  common.draw_text(style.font, style.text,
    string.format("%d%%", common.round(self.zoom * 100)), "center",
    label.x, label.y, label.width, label.height)
  core.pop_clip_rect()
end


return ImageView
