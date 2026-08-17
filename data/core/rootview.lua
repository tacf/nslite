local core = require "core"
local common = require "core.common"
local style = require "core.style"
local Tree = require "core.utils.tree"
local View = require "core.view"
local DocView = require "core.docview"
local EmptyView = require "core.presentations.empty"

local Node = Tree:extend()

Node.LEFT = 1
Node.RIGHT = 2

function Node:new(type)
  self.type = type or "leaf"
  self.position = { x = 0, y = 0 }
  self.size = { x = 0, y = 0 }
  self.nodes = {}
  self.divider = 0.5
  self.tab_scroll = 0
  if self.type == "leaf" then
    self:add_view(EmptyView())
  end
end

function Node:on_mouse_moved(x, y, ...)
  self.hovered_tab = self:get_tab_overlapping_point(x, y)
  self.hovered_tab_close = self:get_tab_close_overlapping_point(x, y)
  if self.type == "leaf" then
    self.active_view:on_mouse_moved(x, y, ...)
  else
    self:propagate("on_mouse_moved", x, y, ...)
  end
end

function Node:on_mouse_released(...)
  if self.type == "leaf" then
    self.active_view:on_mouse_released(...)
  else
    self:propagate("on_mouse_released", ...)
  end
end

local type_map = { up = "vsplit", down = "vsplit", left = "hsplit", right = "hsplit" }


-- locked == true: single-view pane sized by the view itself (not node.divider),
-- so it can enforce min width (TreeView). Can't hold tabs or be focused;
-- divider drags resize it by writing back into the view's size.
function Node:split(dir, view, locked)
  assert(self.type == "leaf", "Tried to split non-leaf node")
  local type = assert(type_map[dir], "Invalid direction")
  local last_active = core.active_view
  local child = Node()
  child:consume(self)
  self:consume(Node(type))
  local other = Node()
  if view then other:add_view(view) end
  if locked then
    other.locked = locked
    core.set_active_view(last_active)
  end
  if dir == "up" or dir == "left" then
    self:add_child(other)
    self:add_child(child)
  else
    self:add_child(child)
    self:add_child(other)
  end
  return child
end

function Node:close_view(root, view)
  local do_close = function()
    local idx = self:get_view_idx(view)
    if not idx then return end
    if #self.nodes > 1 then
      self:del_child(idx)
      if view == self.active_view then
        self:set_active_view(self.nodes[idx] or self.nodes[#self.nodes])
      else
        self:scroll_tab_into_view(self.active_view)
      end
    else
      local parent = self:get_parent(root)
      local side = (parent.nodes[Node.LEFT] == self) and Node.LEFT or Node.RIGHT
      local other_side = (side == Node.LEFT) and Node.RIGHT or Node.LEFT
      local other = parent.nodes[other_side]
      if other:get_locked_size() then
        self.nodes = {}
        self:add_view(EmptyView())
      else
        parent:consume(other)
        local p = parent
        while p.type ~= "leaf" do
          p = p.nodes[side]
        end
        p:set_active_view(p.active_view)
      end
    end
    core.last_active_view = nil
  end
  view:try_close(do_close)
end

function Node:close_active_view(root)
  self:close_view(root, self.active_view)
end

function Node:add_view(view)
  assert(self.type == "leaf", "Tried to add view to non-leaf node")
  assert(not self.locked, "Tried to add view to locked node")
  if self.nodes[1] and self.nodes[1]:is(EmptyView) then
    self:del_child(1)
  end
  self:add_child(view)
  self:set_active_view(view)
end

function Node:set_active_view(view)
  assert(self.type == "leaf", "Tried to set active view on non-leaf node")
  self.active_view = view
  self:scroll_tab_into_view(view)
  core.set_active_view(view)
end

function Node:get_view_idx(view)
  for i, v in ipairs(self.nodes) do
    if v == view then return i end
  end
end

function Node:get_node_for_view(view)
  if self.type == "leaf" then
    for _, v in ipairs(self.nodes) do
      if v == view then return self end
    end
  else
    return self.nodes[Node.LEFT]:get_node_for_view(view) or self.nodes[Node.RIGHT]:get_node_for_view(view)
  end
end

function Node:get_children(t)
  t = t or {}
  if self.type == "leaf" then
    for _, view in ipairs(self.nodes) do
      table.insert(t, view)
    end
  else
    for _, node in ipairs(self.nodes) do
      node:get_children(t)
    end
  end
  return t
end

function Node:get_divider_overlapping_point(px, py)
  if self.type ~= "leaf" then
    local p = 6
    local x, y, w, h = self:get_divider_rect()
    x, y = x - p, y - p
    w, h = w + p * 2, h + p * 2
    if px > x and py > y and px < x + w and py < y + h then
      return self
    end
    return self.nodes[Node.LEFT]:get_divider_overlapping_point(px, py)
        or self.nodes[Node.RIGHT]:get_divider_overlapping_point(px, py)
  end
end

function Node:get_tab_metrics()
  local h = style.font:get_height() + style.padding.y * 2
  local view_count = #self.nodes
  local tab_width = style.tab_width
  local viewport_x = self.position.x
  local viewport_w = self.size.x
  local overflow = tab_width * view_count > viewport_w
  local max_scroll = math.max(0, tab_width * view_count - viewport_w)
  self.tab_scroll = common.clamp(self.tab_scroll or 0, 0, max_scroll)
  return tab_width, h, overflow, viewport_x, viewport_w, max_scroll
end

function Node:get_tab_bar_overlapping_point(px, py)
  if #self.nodes <= 1 then return false end
  local _, h = self:get_tab_metrics()
  return px >= self.position.x and px < self.position.x + self.size.x
      and py >= self.position.y and py < self.position.y + h
end

function Node:get_tab_overlapping_point(px, py)
  if not self:get_tab_bar_overlapping_point(px, py) then return nil end
  local tw, _, _, viewport_x, viewport_w = self:get_tab_metrics()
  if px < viewport_x or px >= viewport_x + viewport_w then return nil end
  local idx = math.floor((px - viewport_x + self.tab_scroll) / tw) + 1
  return idx <= #self.nodes and idx or nil
end

function Node:get_tab_close_overlapping_point(px, py)
  local idx = self:get_tab_overlapping_point(px, py)
  if not idx then return nil end
  local x, _, w, h = self:get_tab_rect(idx)
  if px >= x + w - h then return idx end
end

function Node:scroll_tabs(direction)
  local tw, _, overflow, _, _, max_scroll = self:get_tab_metrics()
  if overflow then
    self.tab_scroll = common.clamp(self.tab_scroll + direction * tw, 0, max_scroll)
  end
end

function Node:scroll_tab_into_view(view)
  local idx = self:get_view_idx(view)
  if not idx then return end
  local tw, _, overflow, _, viewport_w, max_scroll = self:get_tab_metrics()
  if not overflow then
    self.tab_scroll = 0
    return
  end
  local tab_left = (idx - 1) * tw
  local tab_right = tab_left + tw
  if tab_left < self.tab_scroll then
    self.tab_scroll = tab_left
  elseif tab_right > self.tab_scroll + viewport_w then
    self.tab_scroll = tab_right - viewport_w
  end
  self.tab_scroll = common.clamp(self.tab_scroll, 0, max_scroll)
end

function Node:get_child_overlapping_point(x, y)
  local child
  if self.type == "leaf" then
    return self
  elseif self.type == "hsplit" then
    child = (x < self.nodes[Node.RIGHT].position.x) and self.nodes[Node.LEFT] or self.nodes[Node.RIGHT]
  elseif self.type == "vsplit" then
    child = (y < self.nodes[Node.RIGHT].position.y) and self.nodes[Node.LEFT] or self.nodes[Node.RIGHT]
  end
  return child:get_child_overlapping_point(x, y)
end

function Node:get_tab_rect(idx)
  local tw, h, _, viewport_x = self:get_tab_metrics()
  return viewport_x + (idx - 1) * tw - self.tab_scroll, self.position.y, tw, h
end

function Node:get_divider_rect()
  local x, y = self.position.x, self.position.y
  if self.type == "hsplit" then
    return x + self.nodes[Node.LEFT].size.x, y, style.divider_size, self.size.y
  elseif self.type == "vsplit" then
    return x, y + self.nodes[Node.LEFT].size.y, self.size.x, style.divider_size
  end
end

function Node:get_locked_size()
  if self.type == "leaf" then
    if self.locked then
      local size = self.active_view.size
      return size.x, size.y
    end
  else
    local x1, y1 = self.nodes[Node.LEFT]:get_locked_size()
    local x2, y2 = self.nodes[Node.RIGHT]:get_locked_size()
    if x1 and x2 then
      local dsx = (x1 < 1 or x2 < 1) and 0 or style.divider_size
      local dsy = (y1 < 1 or y2 < 1) and 0 or style.divider_size
      return x1 + x2 + dsx, y1 + y2 + dsy
    end
  end
end

local function copy_position_and_size(dst, src)
  dst.position.x, dst.position.y = src.position.x, src.position.y
  dst.size.x, dst.size.y = src.size.x, src.size.y
end


-- calculating the sizes is the same for hsplits and vsplits, except the x/y
-- axis are swapped; this function lets us use the same code for both
local function calc_split_sizes(self, x, y, x1, x2)
  local n
  local ds = (x1 and x1 < 1 or x2 and x2 < 1) and 0 or style.divider_size
  if x1 then
    n = x1 + ds
  elseif x2 then
    n = self.size[x] - x2
  else
    n = math.floor(self.size[x] * self.divider)
  end

  -- syncronize divider position
  if self.size[x] > 0 then
    self.divider = n / self.size[x]
  end

  self.nodes[Node.LEFT].position[x] = self.position[x]
  self.nodes[Node.LEFT].position[y] = self.position[y]
  self.nodes[Node.LEFT].size[x] = n - ds
  self.nodes[Node.LEFT].size[y] = self.size[y]
  self.nodes[Node.RIGHT].position[x] = self.position[x] + n
  self.nodes[Node.RIGHT].position[y] = self.position[y]
  self.nodes[Node.RIGHT].size[x] = self.size[x] - n
  self.nodes[Node.RIGHT].size[y] = self.size[y]
end


function Node:update_layout()
  if self.type == "leaf" then
    local av = self.active_view
    if #self.nodes > 1 then
      local _, th, _, _, viewport_w = self:get_tab_metrics()
      if self.tab_viewport_width ~= viewport_w then
        self.tab_viewport_width = viewport_w
        self:scroll_tab_into_view(av)
      end
      av.position.x, av.position.y = self.position.x, self.position.y + th
      av.size.x, av.size.y = self.size.x, self.size.y - th
    else
      copy_position_and_size(av, self)
    end
  else
    local x1, y1 = self.nodes[Node.LEFT]:get_locked_size()
    local x2, y2 = self.nodes[Node.RIGHT]:get_locked_size()
    if self.type == "hsplit" then
      calc_split_sizes(self, "x", "y", x1, x2)
    elseif self.type == "vsplit" then
      calc_split_sizes(self, "y", "x", y1, y2)
    end
    self:propagate("update_layout")
  end
end

function Node:update()
  if self.type == "leaf" then
    for _, view in ipairs(self.nodes) do
      view:update()
    end
  else
    self:propagate("update")
  end
end

function Node:draw_tabs()
  local tw, h, overflow, viewport_x, viewport_w, max_scroll = self:get_tab_metrics()
  local x, y = self.position.x, self.position.y
  local ds = style.divider_size
  core.push_clip_rect(x, y, self.size.x, h)
  renderer.draw_rect(x, y, self.size.x, h, style.background2)
  renderer.draw_rect(x, y + h - ds, self.size.x, ds, style.divider)

  core.push_clip_rect(viewport_x, y, viewport_w, h)
  for i, view in ipairs(self.nodes) do
    local x = viewport_x + (i - 1) * tw - self.tab_scroll
    local w = tw
    local text = view:get_name()
    local is_active = view == self.active_view
    local color = style.dim
    if is_active then
      color = style.text
      renderer.draw_rect(x, y, w, h, style.background)
      renderer.draw_rect(x + w, y, ds, h, style.divider)
      renderer.draw_rect(x - ds, y, ds, h, style.divider)
    end
    if i == self.hovered_tab then
      color = style.text
    end
    core.push_clip_rect(x, y, w, h)
    local close_x = x + w - h
    local text_x = x + style.padding.x
    local text_w = math.max(0, w - h - style.padding.x * 2)
    local label, cropped = common.crop_text(style.font, text, text_w, "...")
    common.draw_text(style.font, color, label,
      cropped and "left" or "center", text_x, y, text_w, h)
    if is_active or i == self.hovered_tab then
      local close_color = i == self.hovered_tab_close and style.accent or color
      common.draw_text(style.icon_font, close_color, "x", "center", close_x, y, h, h)
    end
    core.pop_clip_rect()
  end
  core.pop_clip_rect()

  core.pop_clip_rect()
end

function Node:draw()
  if self.type == "leaf" then
    if #self.nodes > 1 then
      self:draw_tabs()
    end
    local pos, size = self.active_view.position, self.active_view.size
    core.push_clip_rect(pos.x, pos.y, size.x + pos.x % 1, size.y + pos.y % 1)
    self.active_view:draw()
    core.pop_clip_rect()
  else
    local x, y, w, h = self:get_divider_rect()
    renderer.draw_rect(x, y, w, h, style.divider)
    self:propagate("draw")
  end
end

local RootView = View:extend()

function RootView:new()
  RootView.super.new(self)
  self.root_node = Node()
  self.deferred_draws = {}
  self.floating_views = {}
  self.mouse = { x = 0, y = 0 }
end

function RootView:defer_draw(fn, ...)
  table.insert(self.deferred_draws, 1, { fn = fn, ... })
end

-- Floating views are drawn on top of the node tree, positioned freely
-- (independent of the split layout). While a floating view reports itself
-- as shown, it captures input as a modal overlay.
function RootView:add_floating_view(view)
  view.floating = true
  table.insert(self.floating_views, view)
end

function RootView:get_active_floating_view()
  for _, view in ipairs(self.floating_views) do
    if view:is_shown() then
      return view
    end
  end
end

function RootView:get_active_node()
  return self.root_node:get_node_for_view(core.active_view)
end

function RootView:open_view(view, is_same)
  local node = self:get_active_node()
  if node.locked and core.last_active_view then
    core.set_active_view(core.last_active_view)
    node = self:get_active_node()
  end
  assert(not node.locked, "Cannot open view on locked node")
  if is_same then
    for _, existing in ipairs(node.nodes) do
      if is_same(existing) then
        node:set_active_view(existing)
        return existing, false
      end
    end
  end
  node:add_view(view)
  self.root_node:update_layout()
  return view, true
end

function RootView:open_doc(doc, ViewType)
  ViewType = ViewType or DocView
  local view, is_new = self:open_view(ViewType(doc), function(existing)
    return existing.doc == doc
  end)
  if is_new then
    view:scroll_to_line(view.doc:get_selection(), true, true)
  end
  return view
end

function RootView:on_mouse_pressed(button, x, y, clicks)
  -- a shown floating view is modal: it captures the click, and a click
  -- outside its bounds dismisses it
  local fv = self:get_active_floating_view()
  if fv then
    if fv:floating_contains_point(x, y) then
      core.set_active_view(fv)
      fv:on_mouse_pressed(button, x, y, clicks)
    else
      fv:exit()
    end
    return
  end

  local div = self.root_node:get_divider_overlapping_point(x, y)
  if div then
    self.dragged_divider = div
    self.resized_detached = false
    return
  end
  local node = self.root_node:get_child_overlapping_point(x, y)
  local idx = node:get_tab_overlapping_point(x, y)
  if idx then
    local close_idx = node:get_tab_close_overlapping_point(x, y)
    if button == "left" and close_idx then
      node:close_view(self.root_node, node.nodes[close_idx])
    else
      node:set_active_view(node.nodes[idx])
    end
    if button == "middle" then
      node:close_active_view(self.root_node)
    end
  elseif not node:get_tab_bar_overlapping_point(x, y) then
    core.set_active_view(node.active_view)
    node.active_view:on_mouse_pressed(button, x, y, clicks)
  end
end

function RootView:on_mouse_released(...)
  if self.dragged_divider then
    self.dragged_divider = nil
    self.resized_detached = nil
  end
  self.root_node:on_mouse_released(...)
end

function RootView:on_mouse_moved(x, y, dx, dy)
  self.mouse.x, self.mouse.y = x, y
  local fv = self:get_active_floating_view()
  if fv then
    fv:on_mouse_moved(x, y, dx, dy)
    system.set_cursor(fv.cursor)
    return
  end

  if self.dragged_divider then
    local node = self.dragged_divider
    local divider_size = style.divider_size
    local detach_threshold = style.font:get_height() * 3

    -- only follow the cursor while attached
    if not self.resize_detached then
      if node.type == "hsplit" then
        node.divider = node.divider + dx / node.size.x
      else
        node.divider = node.divider + dy / node.size.y
      end
      node.divider = common.clamp(node.divider, 0.01, 0.99)

      local ax, ay = node.nodes[Node.LEFT]:get_locked_size()
      local bx, by = node.nodes[Node.RIGHT]:get_locked_size()
      if node.type == "hsplit" then
        if ax then node.nodes[Node.LEFT].active_view.size.x = node.size.x * node.divider - divider_size end
        if bx then node.nodes[Node.RIGHT].active_view.size.x = node.size.x * (1 - node.divider) - divider_size end
      else
        if ay then node.nodes[Node.LEFT].active_view.size.y = node.size.y * node.divider - divider_size end
        if by then node.nodes[Node.RIGHT].active_view.size.y = node.size.y * (1 - node.divider) - divider_size end
      end
    end

    -- freeze while detached; unfreeze when the cursor returns within range
    -- this accounts for nodes that internally lock their size (like setting a min/max size, eg, TreeView)
    local divider_pos
    if node.type == "hsplit" then
      divider_pos = node.position.x + node.size.x * node.divider
    else
      divider_pos = node.position.y + node.size.y * node.divider
    end
    local dist = node.type == "hsplit" and (x - divider_pos) or (y - divider_pos)
    if math.abs(dist) > detach_threshold then
      self.resize_detached = true
    elseif self.root_node:get_divider_overlapping_point(x, y) then
      self.resize_detached = false
    end

    return
  end


  self.root_node:on_mouse_moved(x, y, dx, dy)

  local node = self.root_node:get_child_overlapping_point(x, y)
  local div = self.root_node:get_divider_overlapping_point(x, y)
  if div then
    system.set_cursor(div.type == "hsplit" and "sizeh" or "sizev")
  elseif node:get_tab_bar_overlapping_point(x, y) then
    system.set_cursor("arrow")
  else
    system.set_cursor(node.active_view.cursor)
  end
end

function RootView:on_mouse_wheel(delta, ...)
  local fv = self:get_active_floating_view()
  if fv then
    fv:on_mouse_wheel(delta, ...)
    return
  end
  local x, y = self.mouse.x, self.mouse.y
  local node = self.root_node:get_child_overlapping_point(x, y)
  if node:get_tab_bar_overlapping_point(x, y) then
    local _, _, overflow = node:get_tab_metrics()
    if overflow and delta ~= 0 then
      node:scroll_tabs(delta > 0 and -1 or 1)
    end
    return
  end
  node.active_view:on_mouse_wheel(delta, ...)
end

function RootView:on_text_input(...)
  core.active_view:on_text_input(...)
end

function RootView:update()
  copy_position_and_size(self.root_node, self)
  self.root_node:update()
  self.root_node:update_layout()
  for _, view in ipairs(self.floating_views) do
    view:update()
  end
end

function RootView:draw()
  self.root_node:draw()
  while #self.deferred_draws > 0 do
    local t = table.remove(self.deferred_draws)
    t.fn(table.unpack(t))
  end
  -- floating views draw on top of everything, without layout clipping
  for _, view in ipairs(self.floating_views) do
    if view:is_shown() then
      view:draw()
      while #self.deferred_draws > 0 do
        local t = table.remove(self.deferred_draws)
        t.fn(table.unpack(t))
      end
    end
  end
end

return RootView
