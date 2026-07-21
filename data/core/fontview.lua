local common = require "core.common"
local style = require "core.style"
local View = require "core.view"


local FontView = View:extend()

local specimens = {
  { size = 18, text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ  abcdefghijklmnopqrstuvwxyz" },
  { size = 24, text = "0123456789  !@#$%&*?" },
  { size = 36, text = "Lorem ipsum dolor sit amet" },
  { size = 48, text = "The quick brown fox" },
  { size = 72, text = "Aa Ee Ii Oo Uu Ll" },
}


function FontView:new(filename)
  FontView.super.new(self)
  self.filename = filename
  self.scrollable = true
  self.fonts = {}
  for _, specimen in ipairs(specimens) do
    table.insert(self.fonts, renderer.font.load(filename, specimen.size * SCALE))
  end
end

function FontView:get_name()
  return self.filename:match("[^/\\]+$") or self.filename
end

function FontView:get_scrollable_size()
  local height = style.big_font:get_height() + style.font:get_height()
      + style.padding.y * 7
  for i in ipairs(specimens) do
    height = height + style.font:get_height() + self.fonts[i]:get_height()
        + style.padding.y * 5 + style.divider_size
  end
  return height
end

function FontView:draw()
  self:draw_background(style.background)

  local x, y = self:get_content_offset()
  local padding_x = style.padding.x * 2
  local width = math.max(0, self.size.x - padding_x * 2 - style.scrollbar_size)
  x = x + padding_x
  y = y + style.padding.y * 2

  renderer.draw_text(style.big_font, self:get_name(), x, y, style.accent)
  y = y + style.big_font:get_height() + style.padding.y
  renderer.draw_text(style.font, self.filename, x, y, style.dim)
  y = y + style.font:get_height() + style.padding.y * 2

  for i, specimen in ipairs(specimens) do
    local font = self.fonts[i]
    renderer.draw_text(
      style.font, string.format("%d px", specimen.size), x, y, style.dim)
    y = y + style.font:get_height() + style.padding.y

    local text_x = x
    local text_width = font:get_width(specimen.text)
    if text_width < width then
      text_x = x + common.round((width - text_width) / 2)
    end
    renderer.draw_text(font, specimen.text, text_x, y, style.text)
    y = y + font:get_height() + style.padding.y * 2

    renderer.draw_rect(x, y, width, style.divider_size, style.divider)
    y = y + style.padding.y * 2
  end

  self:draw_scrollbar()
end

return FontView
