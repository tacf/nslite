local core = require "core"
local common = require "core.common"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local View = require "core.view"


local SingleLineDoc = Doc:extend()

function SingleLineDoc:insert(line, col, text)
  SingleLineDoc.super.insert(self, line, col, text:gsub("\n", ""))
end


local CommandView = DocView:extend()

local max_suggestions = 10

local blink_period = 0.8

local noop = function() end

local default_state = {
  submit = noop,
  suggest = noop,
  cancel = noop,
}


function CommandView:new()
  CommandView.super.new(self, SingleLineDoc())
  self.suggestion_idx = 1
  self.suggestions = {}
  self.suggestions_height = 0
  self.last_change_id = 0
  self.gutter_width = 0
  self.gutter_text_brightness = 0
  self.selection_offset = 0
  self.state = default_state
  self.font = "font"
  self.size.y = 0
  self.label = ""
  -- floating palette configuration (overridable)
  self.floating = true
  self.palette_width = math.ceil(600 * SCALE)
  self.palette_top = 0.1
end


function CommandView:get_name()
  return View.get_name(self)
end


function CommandView:get_scrollable_size()
  return 0
end


function CommandView:scroll_to_make_visible()
  -- no-op function to disable this functionality
end


function CommandView:get_text()
  return self.doc:get_text(1, 1, 1, math.huge)
end


function CommandView:set_text(text, select)
  self.doc:remove(1, 1, math.huge, math.huge)
  self.doc:text_input(text)
  if select then
    self.doc:set_selection(math.huge, math.huge, 1, 1)
  end
end


function CommandView:move_suggestion_idx(dir)
  local n = self.suggestion_idx + dir
  self.suggestion_idx = common.clamp(n, 1, #self.suggestions)
  self:complete()
  self.last_change_id = self.doc:get_change_id()
end


function CommandView:complete()
  if #self.suggestions > 0 then
    self:set_text(self.suggestions[self.suggestion_idx].text)
  end
end


function CommandView:submit()
  local suggestion = self.suggestions[self.suggestion_idx]
  local text = self:get_text()
  local submit = self.state.submit
  self:exit(true)
  submit(text, suggestion)
end


function CommandView:enter(text, submit, suggest, cancel)
  if self.state ~= default_state then
    return
  end
  self.state = {
    submit = submit or noop,
    suggest = suggest or noop,
    cancel = cancel or noop,
  }
  core.set_active_view(self)
  self:update_suggestions()
  self.gutter_text_brightness = 100
  self.label = text .. ": "
end


function CommandView:exit(submitted, inexplicit)
  if core.active_view == self then
    core.set_active_view(core.last_active_view)
  end
  local cancel = self.state.cancel
  self.state = default_state
  self.doc:reset()
  self.suggestions = {}
  if not submitted then cancel(not inexplicit) end
end


function CommandView:get_gutter_width()
  return self.gutter_width
end


function CommandView:get_suggestion_line_height()
  return self:get_font():get_height() + style.padding.y
end


function CommandView:update_suggestions()
  local t = self.state.suggest(self:get_text()) or {}
  local res = {}
  for i, entry in ipairs(t) do
    if i == max_suggestions then
      break
    end
    local item = entry
    if type(item) == "string" then
      item = { text = item }
    end
    res[i] = item
  end
  self.suggestions = res
  self.suggestion_idx = 1
end


-- the height of the (animated) input box
function CommandView:get_input_height()
  return math.ceil(self.size.y)
end


-- returns x, y, w, h for the input box and the suggestions box
function CommandView:get_floating_rects()
  local ih = self:get_input_height()
  local ix, iy, iw = self.position.x, self.position.y, self.size.x
  local dh = (#self.suggestions > 0) and style.divider_size or 0
  local sh = math.ceil(self.suggestions_height)
  return ix, iy, iw, ih, ix, iy + ih + dh, iw, sh
end


function CommandView:is_shown()
  return self.floating and self.size.y > 0
end


function CommandView:floating_contains_point(x, y)
  local ix, iy, iw, ih, sx, sy, sw, sh = self:get_floating_rects()
  local in_input = x >= ix and x < ix + iw and y >= iy and y < iy + ih
  local in_sugg = #self.suggestions > 0
    and x >= sx and x < sx + sw and y >= sy and y < sy + sh
  return in_input or in_sugg
end


-- map a screen point to a suggestion index, or nil
function CommandView:suggestion_at_point(x, y)
  if #self.suggestions == 0 then return end
  local _, _, _, _, sx, sy, sw, sh = self:get_floating_rects()
  if x < sx or x >= sx + sw or y < sy or y >= sy + sh then return end
  local lh = self:get_suggestion_line_height()
  local i = math.floor((y - sy) / lh) + 1
  if i >= 1 and i <= #self.suggestions then return i end
end


function CommandView:on_mouse_moved(x, y, ...)
  View.on_mouse_moved(self, x, y, ...)
  self.cursor = "arrow"
  local i = self:suggestion_at_point(x, y)
  if i then
    self.suggestion_idx = i
  end
end


function CommandView:on_mouse_pressed(button, x, y, clicks)
  local i = self:suggestion_at_point(x, y)
  if i then
    self.suggestion_idx = i
    self:submit()
  end
end


function CommandView:update()
  CommandView.super.update(self)

  if core.active_view ~= self and self.state ~= default_state then
    self:exit(false, true)
  end

  -- update suggestions if text has changed
  if self.last_change_id ~= self.doc:get_change_id() then
    self:update_suggestions()
    self.last_change_id = self.doc:get_change_id()
  end

  -- update gutter text color brightness
  self:move_towards("gutter_text_brightness", 0, 0.1)

  -- update gutter width
  local dest = self:get_font():get_width(self.label) + style.padding.x
  if self.size.y <= 0 then
    self.gutter_width = dest
  else
    self:move_towards("gutter_width", dest)
  end

  -- update suggestions box height
  local lh = self:get_suggestion_line_height()
  local dest = #self.suggestions * lh
  self:move_towards("suggestions_height", dest)

  -- update suggestion highlight offset
  local dest = (self.suggestion_idx - 1) * self:get_suggestion_line_height()
  self:move_towards("selection_offset", dest)

  -- update size based on whether this is the active_view
  local dest = 0
  if self == core.active_view then
    dest = style.font:get_height() + style.padding.y * 2
  end
  self:move_towards(self.size, "y", dest)

  -- position the floating palette (independent of the split layout)
  if self.floating then
    local root = core.root_view
    self.size.x = self.palette_width
    self.position.x = math.floor((root.size.x - self.size.x) / 2)
    self.position.y = math.floor(root.size.y * self.palette_top)
  end
end


function CommandView:draw_line_highlight()
  -- no-op function to disable this functionality
end


-- Fakes a soft drop shadow by stacking translucent rounded rects that expand
-- outward from the palette, strongest near the edge and fading with distance.
local function draw_shadow(x, y, w, h, radius)
  local size = style.commandview_shadow_size or 0
  if size <= 0 then return end
  local c = style.commandview_shadow_color or { 0, 0, 0 }
  local offset = style.commandview_shadow_offset or math.ceil(2 * SCALE)
  local max_alpha = c[4] or 90
  local steps = math.min(math.floor(size), 16)
  for i = steps, 1, -1 do
    local o = size * i / steps
    local a = max_alpha * (1 - (i - 1) / steps)
    common.draw_rounded_rect(x - o, y - o + offset, w + o * 2, h + o * 2,
      radius + o, { c[1] or 0, c[2] or 0, c[3] or 0, a })
  end
end


-- self-contained floating command palette rendering
function CommandView:draw()
  if not self.floating then
    return CommandView.super.draw(self)
  end

  local root = core.root_view
  local font = self:get_font()
  local fh = font:get_height()
  local radius = style.commandview_corner_radius or 0

  local ix, iy, iw, ih, sx, sy, sw, sh = self:get_floating_rects()
  local has_sugg = #self.suggestions > 0
  local total_h = ih + (has_sugg and (style.divider_size + sh) or 0)

  -- modal overlay dimming the editor behind the palette
  local overlay = style.commandview_overlay_color or { 0, 0, 0, 110 }
  renderer.draw_rect(0, 0, root.size.x, root.size.y, overlay)

  -- drop shadow behind the whole palette
  draw_shadow(ix, iy, iw, total_h, radius)

  -- input box background (top corners rounded; bottom rounded only if alone)
  local input_corners = {
    tl = true, tr = true, bl = not has_sugg, br = not has_sugg,
  }
  common.draw_rounded_rect(ix, iy, iw, ih, radius, style.background, input_corners)

  -- input contents (label + typed text + caret), clipped to the box
  core.push_clip_rect(ix, iy, iw, ih)
  local ty = iy + (ih - fh) / 2
  local tx = ix + style.padding.x
  local lcolor = common.lerp(style.text, style.accent, self.gutter_text_brightness / 100)
  tx = renderer.draw_text(font, self.label, tx, ty, lcolor)
  local text = self:get_text()
  renderer.draw_text(font, text, tx, ty, style.accent)
  if self == core.active_view
  and self.blink_timer < blink_period / 2
  and system.window_has_focus() then
    local _, col = self.doc:get_selection()
    local cx = tx + font:get_width(text:sub(1, col - 1))
    renderer.draw_rect(cx, iy + style.padding.y, style.caret_width, fh, style.caret)
  end
  core.pop_clip_rect()

  -- suggestions box below the input, sprawling downward
  if has_sugg then
    local dh = style.divider_size
    renderer.draw_rect(ix, iy + ih, iw, dh, style.divider)
    common.draw_rounded_rect(sx, sy, sw, sh, radius, style.background3,
      { tl = false, tr = false, bl = true, br = true })

    -- selection highlight
    local lh = self:get_suggestion_line_height()
    core.push_clip_rect(sx, sy, sw, sh)
    renderer.draw_rect(sx, sy + self.selection_offset, sw, lh, style.line_highlight)

    -- items
    local tw = sw - style.padding.x * 2
    for i, item in ipairs(self.suggestions) do
      local color = (i == self.suggestion_idx) and style.accent or style.text
      local y = sy + (i - 1) * lh
      local x = sx + style.padding.x
      common.draw_text(font, color, item.text, "left", x, y, tw, lh)
      if item.info then
        common.draw_text(font, style.dim, item.info, "right", x, y, tw, lh)
      end
    end
    core.pop_clip_rect()
  end
end


return CommandView
