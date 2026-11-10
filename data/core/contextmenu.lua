local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"


-- Providers describe menus; ContextMenuView owns their presentation and input.
local contextmenu = { registry = {} }


local function scope_matches(scope, view)
  if scope == nil then
    return true
  elseif type(scope) == "function" then
    return scope(view)
  elseif type(scope) == "table" then
    return scope == view or (view ~= nil and view.is ~= nil and view:is(scope))
  end
  return false
end


-- Scope: a View class, module name, predicate, or nil (all views).
-- Items: a list or function(view, x, y) returning a list. Entries support
-- text, command/action, nested items, and visible/enabled predicates.
-- A plain string is a label; "-" is a separator.
function contextmenu.add(scope, items)
  if items == nil then
    items, scope = scope, nil
  end
  assert(type(items) == "table" or type(items) == "function",
    "expected menu items or a provider function")
  if type(scope) == "string" then scope = require(scope) end
  table.insert(contextmenu.registry, { scope = scope, items = items })
end


local function option(value, view, x, y)
  if type(value) == "function" then return value(view, x, y) end
  return value
end


local function normalize_items(items, view, x, y)
  items = option(items, view, x, y)
  local res = {}
  for _, item in ipairs(items or {}) do
    if item == "-" or (type(item) == "table" and item.separator) then
      if #res > 0 and not res[#res].separator then
        table.insert(res, { separator = true })
      end
    elseif type(item) == "table" then
      if option(item.visible, view, x, y) ~= false then
        local submenu = item.items and normalize_items(item.items, view, x, y)
        if submenu and #submenu == 0 then submenu = nil end
        -- Keep a fallback action, but omit empty submenu-only parents.
        if not item.items or submenu or item.action or item.command then
          local enabled = option(item.enabled, view, x, y) ~= false
          if enabled and item.command and not item.action and not submenu then
            local cmd = command.map[item.command]
            local ok, valid = false, false
            if cmd then ok, valid = pcall(cmd.predicate) end
            enabled = ok and not not valid
          end
          table.insert(res, {
            text = item.text or item.label or item.name or "",
            info = item.info or (item.command and keymap.get_binding(item.command)),
            command = item.command,
            action = item.action,
            submenu = submenu,
            enabled = enabled,
          })
        end
      end
    elseif type(item) == "string" then
      table.insert(res, { text = item, enabled = false })
    end
  end
  while #res > 0 and res[#res].separator do table.remove(res) end
  return res
end


-- Resolve in the target's command context without changing focus history.
-- Always restore it, including when a plugin provider raises an error.
function contextmenu.resolve(view, x, y)
  local previous, last = core.active_view, core.last_active_view
  core.active_view = view
  local ok, result = pcall(function()
    local res = {}
    local function append(items)
      items = normalize_items(items, view, x, y)
      if #items == 0 then return end
      if #res > 0 then table.insert(res, { separator = true }) end
      for _, item in ipairs(items) do table.insert(res, item) end
    end
    for _, reg in ipairs(contextmenu.registry) do
      if scope_matches(reg.scope, view) then append(reg.items) end
    end
    if view and view.get_context_menu then append(view:get_context_menu(x, y)) end
    return res
  end)
  core.active_view, core.last_active_view = previous, last
  if not ok then error(result, 0) end
  return result
end


function contextmenu.open(view, x, y)
  return core.context_menu and core.context_menu:open(view, x, y) or false
end


return contextmenu
