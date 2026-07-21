local core = require "core"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local DocView = require "core.docview"
local StatusView = require "core.statusview"


local clients = setmetatable({}, { __mode = "k" })


local function primary_modifier_down()
  return keymap.modkeys[PLATFORM == "macOS" and "cmd" or "ctrl"]
end


local function matching_server(filename)
  local settings = config.lsp
  if not settings then return end
  for _, server in ipairs(settings.servers or {}) do
    for _, language in ipairs(server.languages or {}) do
      for _, pattern in ipairs(language.files or {}) do
        if filename:find(pattern) then
          return server, language.id
        end
      end
    end
  end
end


local function server_name(server)
  if server.name then return server.name end
  local command = server.command and server.command[1]
  if not command then return "configured" end
  command = command:gsub("\\", "/")
  return command:match("[^/]+$") or command
end


local function get_client(server)
  local cached = clients[server]
  if cached then return cached.client, cached.error end

  local root = core.project_path(server.root or core.project_dir)
  local client, err = lsp.start(server.command, root)
  cached = { client = client, error = err }
  clients[server] = cached
  if err then core.error("LSP: %s", err) end
  return client, err
end


local statusview_get_items = StatusView.get_items
function StatusView:get_items(...)
  local left, right = statusview_get_items(self, ...)
  local view = core.active_view
  if getmetatable(view) ~= DocView then return left, right end

  local filename = view.doc:get_filename()
  local server = filename and matching_server(filename)
  if not server then return left, right end

  local cached = clients[server]
  local color = cached and cached.client and style.text or style.dim
  local label = "LSP: " .. server_name(server)
  if cached and cached.error then
    color = style.accent
    label = label .. " (error)"
  end
  table.insert(right, self.separator)
  table.insert(right, color)
  table.insert(right, label)
  return left, right
end


local function pointer_is_over_text(view, x, y)
  return x >= view.position.x + view:get_gutter_width()
    and x < view.position.x + view.size.x
    and y >= view.position.y
    and y < view.position.y + view.size.y
    and not view:scrollbar_overlaps_point(x, y)
end


local function clear_link(view, pointer_over_text)
  local changed = view.lsp_link ~= nil
  view.lsp_link = nil
  if pointer_over_text then
    view.cursor = "ibeam"
    system.set_cursor("ibeam")
  end
  if changed then core.redraw = true end
end


local function update_link(view)
  if view ~= core.active_view or view.mouse_selecting then
    clear_link(view, false)
    return
  end

  local mouse = core.root_view.mouse
  local pointer_over_text = pointer_is_over_text(view, mouse.x, mouse.y)
  local filename = view.doc:get_filename()
  if not primary_modifier_down() or not pointer_over_text or not filename then
    clear_link(view, pointer_over_text)
    return
  end

  local server, language_id = matching_server(filename)
  if not server then
    clear_link(view, true)
    return
  end
  local client = get_client(server)
  if not client then
    clear_link(view, true)
    return
  end

  local line, col = view:resolve_screen_position(mouse.x, mouse.y)
  local state, target, target_line, target_character, col1, col2 =
    client:definition(view.doc._document, language_id, line, col)
  if not state then
    local cached = clients[server]
    cached.error = target
    cached.client = nil
    client:close()
    core.error("LSP: %s", target)
    clear_link(view, true)
    return
  end
  if state ~= "ready" then
    clear_link(view, true)
    if state == "pending" then core.redraw = true end
    return
  end

  local old = view.lsp_link
  view.lsp_link = {
    line = line,
    col1 = col1,
    col2 = col2,
    revision = view.doc:get_revision(),
    target = target,
    target_line = target_line,
    target_character = target_character,
  }
  view.cursor = "hand"
  system.set_cursor("hand")
  if not old or old.line ~= line or old.col1 ~= col1 or old.col2 ~= col2
  or old.target ~= target or old.target_line ~= target_line
  or old.target_character ~= target_character then
    core.redraw = true
  end
end


local docview_update = DocView.update
function DocView:update(...)
  docview_update(self, ...)
  update_link(self)
end


local docview_mouse_pressed = DocView.on_mouse_pressed
function DocView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" and primary_modifier_down() then
    update_link(self)
    local link = self.lsp_link
    if link and link.revision == self.doc:get_revision() then
      local line, col = self:resolve_screen_position(x, y)
      if line == link.line and col >= link.col1 and col < link.col2 then
        local view = core.open_file(link.target)
        local target_line, target_col = lsp.resolve_position(
          view.doc._document, link.target_line, link.target_character)
        view.doc:set_selection(target_line, target_col)
        view:scroll_to_line(target_line, false, true)
        view:scroll_to_make_visible(target_line, target_col)
        clear_link(self, false)
        return
      end
    end
  end
  return docview_mouse_pressed(self, button, x, y, clicks)
end


local docview_draw_line_body = DocView.draw_line_body
function DocView:draw_line_body(idx, x, y)
  docview_draw_line_body(self, idx, x, y)
  local link = self.lsp_link
  if not link or link.line ~= idx or link.revision ~= self.doc:get_revision() then
    return
  end

  local font = self:get_font()
  local x1 = x + self:get_col_x_offset(idx, link.col1)
  local x2 = x + self:get_col_x_offset(idx, link.col2)
  local ty = y + self:get_line_text_y_offset()
  local text = self.doc:get_text(idx, link.col1, idx, link.col2)
  renderer.draw_text(font, text, x1, ty, style.lsp_link)
  local thickness = math.max(1, math.floor(SCALE))
  renderer.draw_rect(
    x1, ty + font:get_height() - thickness, x2 - x1, thickness, style.lsp_link)
end
