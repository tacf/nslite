local Object = require "core.object"
local Highlighter = require "core.doc.highlighter"
local syntax = require "core.syntax"
local config = require "core.config"


local Doc = Object:extend()


function Doc:new(filename)
  self:reset()
  if filename then
    self:load(filename)
  end
end


function Doc:reset()
  if self._document then
    self._document:reset()
  else
    self._document = document.new()
  end
  self.selection = { a = { line=1, col=1 }, b = { line=1, col=1 } }
  self.undo_stack = { idx = 1 }
  self.redo_stack = { idx = 1 }
  self.clean_change_id = 1
  self.highlighter = Highlighter(self)
  self:reset_syntax()
end


function Doc:reset_syntax()
  local header = self:get_text(1, 1, self:position_offset(1, 1, 128))
  local syn = syntax.get(self:get_filename() or "", header)
  if self.syntax ~= syn then
    self.syntax = syn
    self.highlighter:reset()
  end
end


function Doc:load(filename)
  local native = self._document or document.new()
  assert(native:load(filename))
  self._document = native
  self.selection = { a = { line=1, col=1 }, b = { line=1, col=1 } }
  self.undo_stack = { idx = 1 }
  self.redo_stack = { idx = 1 }
  self.clean_change_id = 1
  self.highlighter = Highlighter(self)
  self:reset_syntax()
end


function Doc:save(filename)
  assert(self._document:save(filename))
  self:reset_syntax()
  self:clean()
end


function Doc:get_name()
  return self:get_filename() or "unsaved"
end


function Doc:get_filename()
  return self._document:filename()
end


function Doc:is_crlf()
  return self._document:is_crlf()
end


function Doc:set_crlf(enabled)
  self._document:set_crlf(enabled)
end


function Doc:line_count()
  return self._document:line_count()
end


function Doc:get_line(line)
  return self._document:get_line(line)
end


function Doc:each_line()
  local line = 0
  return function()
    line = line + 1
    local text = self:get_line(line)
    if text then return line, text end
  end
end


function Doc:is_dirty()
  return self.clean_change_id ~= self:get_change_id()
end


function Doc:clean()
  self.clean_change_id = self:get_change_id()
end


function Doc:get_change_id()
  return self.undo_stack.idx
end


function Doc:set_selection(line1, col1, line2, col2, swap)
  assert(not line2 == not col2, "expected 2 or 4 arguments")
  if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2 or line1, col2 or col1)
  self.selection.a.line, self.selection.a.col = line1, col1
  self.selection.b.line, self.selection.b.col = line2, col2
end


local function sort_positions(line1, col1, line2, col2)
  if line1 > line2
  or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end


function Doc:get_selection(sort)
  local a, b = self.selection.a, self.selection.b
  if sort then
    return sort_positions(a.line, a.col, b.line, b.col)
  end
  return a.line, a.col, b.line, b.col
end


function Doc:has_selection()
  local a, b = self.selection.a, self.selection.b
  return not (a.line == b.line and a.col == b.col)
end


function Doc:sanitize_selection()
  self:set_selection(self:get_selection())
end


function Doc:sanitize_position(line, col)
  return self._document:sanitize_position(line, col)
end


local function position_offset_func(self, line, col, fn, ...)
  line, col = self:sanitize_position(line, col)
  return fn(self, line, col, ...)
end


local function position_offset_byte(self, line, col, offset)
  return self._document:position_offset(line, col, offset)
end


local function position_offset_linecol(self, line, col, lineoffset, coloffset)
  return self:sanitize_position(line + lineoffset, col + coloffset)
end


function Doc:position_offset(line, col, ...)
  if type(...) ~= "number" then
    return position_offset_func(self, line, col, ...)
  elseif select("#", ...) == 1 then
    return position_offset_byte(self, line, col, ...)
  elseif select("#", ...) == 2 then
    return position_offset_linecol(self, line, col, ...)
  else
    error("bad number of arguments")
  end
end


function Doc:get_text(line1, col1, line2, col2)
  return self._document:get_text(line1, col1, line2, col2)
end


function Doc:get_char(line, col)
  return self._document:get_char(line, col)
end


local function push_undo(undo_stack, time, type, ...)
  undo_stack[undo_stack.idx] = { type = type, time = time, ... }
  undo_stack[undo_stack.idx - config.max_undos] = nil
  undo_stack.idx = undo_stack.idx + 1
end


local function pop_undo(self, undo_stack, redo_stack)
  -- pop command
  local cmd = undo_stack[undo_stack.idx - 1]
  if not cmd then return end
  undo_stack.idx = undo_stack.idx - 1

  -- handle command
  if cmd.type == "insert" then
    local line, col, text = table.unpack(cmd)
    self:raw_insert(line, col, text, redo_stack, cmd.time)

  elseif cmd.type == "remove" then
    local line1, col1, line2, col2 = table.unpack(cmd)
    self:raw_remove(line1, col1, line2, col2, redo_stack, cmd.time)

  elseif cmd.type == "selection" then
    self.selection.a.line, self.selection.a.col = cmd[1], cmd[2]
    self.selection.b.line, self.selection.b.col = cmd[3], cmd[4]
  end

  -- if next undo command is within the merge timeout then treat as a single
  -- command and continue to execute it
  local next = undo_stack[undo_stack.idx - 1]
  if next and math.abs(cmd.time - next.time) < config.undo_merge_timeout then
    return pop_undo(self, undo_stack, redo_stack)
  end
end


function Doc:raw_insert(line, col, text, undo_stack, time)
  local line2, col2 = self._document:insert(line, col, text)

  -- push undo
  push_undo(undo_stack, time, "selection", self:get_selection())
  push_undo(undo_stack, time, "remove", line, col, line2, col2)

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line)
  self:sanitize_selection()
end


function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time)
  -- push undo
  local text = self:get_text(line1, col1, line2, col2)
  push_undo(undo_stack, time, "selection", self:get_selection())
  push_undo(undo_stack, time, "insert", line1, col1, text)

  self._document:remove(line1, col1, line2, col2)

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line1)
  self:sanitize_selection()
end


function Doc:insert(line, col, text)
  self.redo_stack = { idx = 1 }
  line, col = self:sanitize_position(line, col)
  self:raw_insert(line, col, text, self.undo_stack, system.get_time())
end


function Doc:remove(line1, col1, line2, col2)
  self.redo_stack = { idx = 1 }
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = sort_positions(line1, col1, line2, col2)
  self:raw_remove(line1, col1, line2, col2, self.undo_stack, system.get_time())
end


function Doc:undo()
  pop_undo(self, self.undo_stack, self.redo_stack)
end


function Doc:redo()
  pop_undo(self, self.redo_stack, self.undo_stack)
end


function Doc:get_revision()
  return self._document:revision()
end


function Doc:text_input(text)
  if self:has_selection() then
    self:delete_to()
  end
  local line, col = self:get_selection()
  self:insert(line, col, text)
  self:move_to(#text)
end


function Doc:replace(fn)
  local line1, col1, line2, col2, swap
  local had_selection = self:has_selection()
  if had_selection then
    line1, col1, line2, col2, swap = self:get_selection(true)
  else
    local last_line = self:line_count()
    line1, col1, line2, col2 = 1, 1, last_line, #self:get_line(last_line)
  end
  local old_text = self:get_text(line1, col1, line2, col2)
  local new_text, n = fn(old_text)
  if old_text ~= new_text then
    self:insert(line2, col2, new_text)
    self:remove(line1, col1, line2, col2)
    if had_selection then
      line2, col2 = self:position_offset(line1, col1, #new_text)
      self:set_selection(line1, col1, line2, col2, swap)
    end
  end
  return n
end


function Doc:delete_to(...)
  local line, col = self:get_selection(true)
  if self:has_selection() then
    self:remove(self:get_selection())
  else
    local line2, col2 = self:position_offset(line, col, ...)
    self:remove(line, col, line2, col2)
    line, col = sort_positions(line, col, line2, col2)
  end
  self:set_selection(line, col)
end


function Doc:move_to(...)
  local line, col = self:get_selection()
  self:set_selection(self:position_offset(line, col, ...))
end


function Doc:select_to(...)
  local line, col, line2, col2 = self:get_selection()
  line, col = self:position_offset(line, col, ...)
  self:set_selection(line, col, line2, col2)
end


return Doc
