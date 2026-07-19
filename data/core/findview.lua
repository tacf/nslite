local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local Doc = require "core.doc"
local style = require "core.style"
local translate = require "core.doc.translate"
local View = require "core.view"


local SingleLineDoc = Doc:extend()

function SingleLineDoc:insert(line, col, text)
  SingleLineDoc.super.insert(self, line, col, text:gsub("\n", ""))
end


local FindView = View:extend()


local function make_matches(doc, text)
  local state = { matches = {}, by_line = {} }
  if text == "" then return state end

  local needle = text:lower()
  for line, line_text in ipairs(doc.lines) do
    local haystack = line_text:lower()
    local start = 1
    while true do
      local col1, col2 = haystack:find(needle, start, true)
      if not col1 then break end
      local match = { line = line, col1 = col1, col2 = col2 + 1 }
      table.insert(state.matches, match)
      state.by_line[line] = state.by_line[line] or {}
      table.insert(state.by_line[line], match)
      start = col2 + 1
    end
  end
  return state
end


local function match_at_or_after(matches, line, col)
  for i, match in ipairs(matches) do
    if match.line > line or match.line == line and match.col1 >= col then
      return i
    end
  end
  return 1
end


function FindView:new()
  FindView.super.new(self)
  self.cursor = "ibeam"
  self.doc = SingleLineDoc()
  self.font = style.font
  self.width = math.ceil(360 * SCALE)
  self.target = nil
  self.current = 0
  self.last_input_change_id = 0
  self.last_target_change_id = 0
  self.blink_timer = 0
end


function FindView:get_name()
  return View.get_name(self)
end


function FindView:get_text()
  return self.doc:get_text(1, 1, 1, math.huge)
end


function FindView:set_text(text, select)
  self.doc:remove(1, 1, math.huge, math.huge)
  self.doc:text_input(text)
  if select then
    self.doc:set_selection(math.huge, math.huge, 1, 1)
  end
end


function FindView:is_shown()
  return self.target ~= nil
end


function FindView:floating_contains_point(x, y)
  return x >= self.position.x and x < self.position.x + self.size.x
    and y >= self.position.y and y < self.position.y + self.size.y
end


function FindView:clear_matches()
  if self.target then
    self.target.doc.find_state = nil
  end
end


function FindView:update_matches(prefer_origin)
  if not self.target then return end

  local state = make_matches(self.target.doc, self:get_text())
  if #state.matches == 0 then
    self.current = 0
  elseif prefer_origin or self.current < 1 or self.current > #state.matches then
    self.current = match_at_or_after(state.matches, self.origin_line, self.origin_col)
  end
  state.current = self.current
  self.target.doc.find_state = state
  if self.current > 0 then
    self.target:scroll_to_line(state.matches[self.current].line, true)
  end
  self.last_input_change_id = self.doc:get_change_id()
  self.last_target_change_id = self.target.doc:get_change_id()
  core.redraw = true
end


function FindView:show(target)
  self:clear_matches()
  self.target = target
  local line, col = target.doc:get_selection(true)
  self.origin_line, self.origin_col = line, col

  local selected = target.doc:get_text(target.doc:get_selection()):gsub("\n", "")
  self:set_text(selected, true)
  self.current = 0
  self:update_matches(true)
  core.set_active_view(self)
end


function FindView:exit()
  local target = self.target
  if not target then return end
  self:clear_matches()
  self.target = nil
  self.current = 0
  self.doc:reset()
  if core.active_view == self then
    core.set_active_view(target)
  end
  core.redraw = true
end


function FindView:move_match(direction)
  local state = self.target and self.target.doc.find_state
  if not state or #state.matches == 0 then return end
  self.current = (self.current - 1 + direction) % #state.matches + 1
  state.current = self.current
  self.target:scroll_to_line(state.matches[self.current].line, true)
  core.redraw = true
end


function FindView:on_text_input(text)
  self.doc:text_input(text)
  self.blink_timer = 0
end


function FindView:on_mouse_pressed(button, x)
  if button ~= "left" then return end
  local text = self:get_text()
  local font = self.font
  local offset = x - self.position.x - style.padding.x
  local width, col = 0, 1
  for char in common.utf8_chars(text) do
    local char_width = font:get_width(char)
    if offset < width + char_width / 2 then break end
    width = width + char_width
    col = col + #char
  end
  self.doc:set_selection(1, col)
  self.blink_timer = 0
end


function FindView:update()
  if self.target and core.active_view ~= self then
    self:exit()
    return
  end
  if not self.target then return end

  local root = core.root_view
  self.size.x = math.min(self.width, math.max(100, root.size.x - style.padding.x * 2))
  self.size.y = self.font:get_height() + style.padding.y * 2
  self.position.x = root.size.x - self.size.x - style.padding.x
  self.position.y = style.padding.y

  if self.last_input_change_id ~= self.doc:get_change_id() then
    self:update_matches(true)
  elseif self.last_target_change_id ~= self.target.doc:get_change_id() then
    self:update_matches(false)
  end

  local prev = self.blink_timer
  self.blink_timer = (self.blink_timer + 1 / config.fps) % 0.8
  if (self.blink_timer < 0.4) ~= (prev < 0.4) then core.redraw = true end
end


function FindView:draw()
  local font = self.font
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local state = self.target.doc.find_state
  local count = string.format("%d/%d", self.current, #state.matches)
  local count_width = font:get_width(count)
  local text_x = x + style.padding.x
  local text_width = w - style.padding.x * 3 - count_width
  local text_y = y + (h - font:get_height()) / 2
  local text = self:get_text()

  common.draw_rounded_rect(x, y, w, h, math.ceil(4 * SCALE), style.background2)
  renderer.draw_rect(x, y + h - style.divider_size, w, style.divider_size, style.divider)
  core.push_clip_rect(text_x, y, text_width, h)

  local line1, col1, line2, col2 = self.doc:get_selection(true)
  if line1 == 1 and line2 == 1 and col1 ~= col2 then
    local x1 = text_x + font:get_width(text:sub(1, col1 - 1))
    local x2 = text_x + font:get_width(text:sub(1, col2 - 1))
    renderer.draw_rect(x1, y, x2 - x1, h, style.selection)
  end

  renderer.draw_text(font, text == "" and "Find" or text, text_x, text_y,
    text == "" and style.dim or style.text)
  if self.blink_timer < 0.4 and system.window_has_focus() then
    local _, col = self.doc:get_selection()
    local caret_x = text_x + font:get_width(text:sub(1, col - 1))
    renderer.draw_rect(caret_x, y + style.padding.y, style.caret_width,
      font:get_height(), style.caret)
  end
  core.pop_clip_rect()

  common.draw_text(font, style.dim, count, "right", text_x, y, w - style.padding.x * 2, h)
end


local function input_doc()
  return core.active_view.doc
end


local function move_to(fn, select)
  if select then
    input_doc():select_to(fn)
  elseif input_doc():has_selection() then
    local line, col = input_doc():get_selection(fn == translate.previous_char
      or fn == translate.previous_word_start)
    input_doc():set_selection(line, col)
  else
    input_doc():move_to(fn)
  end
end


command.add(FindView, {
  ["find:next"] = function() core.active_view:move_match(1) end,
  ["find:previous"] = function() core.active_view:move_match(-1) end,
  ["find:escape"] = function() core.active_view:exit() end,
  ["find:undo"] = function() input_doc():undo() end,
  ["find:redo"] = function() input_doc():redo() end,
  ["find:cut"] = function()
    if input_doc():has_selection() then
      system.set_clipboard(input_doc():get_text(input_doc():get_selection()))
      input_doc():delete_to(0)
    end
  end,
  ["find:copy"] = function()
    if input_doc():has_selection() then
      system.set_clipboard(input_doc():get_text(input_doc():get_selection()))
    end
  end,
  ["find:paste"] = function() input_doc():text_input(system.get_clipboard():gsub("\r", "")) end,
  ["find:backspace"] = function() input_doc():delete_to(translate.previous_char) end,
  ["find:delete"] = function() input_doc():delete_to(translate.next_char) end,
  ["find:delete-word-left"] = function() input_doc():delete_to(translate.previous_word_start) end,
  ["find:delete-word-right"] = function() input_doc():delete_to(translate.next_word_end) end,
  ["find:select-all"] = function() input_doc():set_selection(1, 1, math.huge, math.huge) end,
  ["find:move-left"] = function() move_to(translate.previous_char) end,
  ["find:move-right"] = function() move_to(translate.next_char) end,
  ["find:move-word-left"] = function() move_to(translate.previous_word_start) end,
  ["find:move-word-right"] = function() move_to(translate.next_word_end) end,
  ["find:move-home"] = function() move_to(translate.start_of_line) end,
  ["find:move-end"] = function() move_to(translate.end_of_line) end,
  ["find:select-left"] = function() move_to(translate.previous_char, true) end,
  ["find:select-right"] = function() move_to(translate.next_char, true) end,
  ["find:select-word-left"] = function() move_to(translate.previous_word_start, true) end,
  ["find:select-word-right"] = function() move_to(translate.next_word_end, true) end,
  ["find:select-home"] = function() move_to(translate.start_of_line, true) end,
  ["find:select-end"] = function() move_to(translate.end_of_line, true) end,
})


return FindView
