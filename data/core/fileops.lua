local core = require "core"

local fileops = {}


local function parent_path(filename)
  return filename:match("^(.*[/\\])[^/\\]+$") or ""
end


local function join_path(parent, name)
  return parent .. (parent:find("[/\\]$") and "" or PATHSEP) .. name
end


-- Resolve the parent directory, but deliberately NOT the final component.
-- This lets us rename/delete a symlink rather than changing its target.
local function entry_path(filename)
  if not filename then return nil end
  local path = core.project_path(filename)
  local name = path:match("([^/\\]+)$")
  if not name then return nil end
  local parent = parent_path(path)
  local absolute = system.absolute_path(parent ~= "" and parent or ".")
  return absolute and join_path(absolute, name) or nil
end


local function child_path(directory, name)
  assert(type(name) == "string" and name ~= "" and name ~= "." and name ~= ".."
    and not name:find("[%z/\\]"), "Enter a file name, not a path")

  local parent = system.absolute_path(core.project_path(directory))
  assert(parent, "Parent directory does not exist")
  local info = system.get_file_info(parent)
  assert(info and info.type == "dir", "Parent path is not a directory")

  return join_path(parent, name)
end


local function existing_file(filename)
  local path = entry_path(filename)
  assert(path, "File no longer exists")
  local info = system.get_file_info(path)
  assert(info and info.type == "file", "Expected a file, not a directory")
  return path
end


-- Capture references before the filesystem mutation. Match the pathname
-- entry, not the target of a symlink: deleting a link must not detach a
-- different document that happens to be open through the target path.
local function references(path)
  local docs, views, seen = {}, {}, {}
  local identity = entry_path(path)

  local function matches(filename)
    local candidate = entry_path(filename)
    return candidate and identity and system.same_path(candidate, identity)
  end

  local function add_doc(doc)
    if doc and not seen[doc] and matches(doc:get_filename()) then
      seen[doc] = true
      table.insert(docs, doc)
    end
  end

  for _, doc in ipairs(core.docs) do add_doc(doc) end
  for _, view in ipairs(core.root_view.root_node:get_children()) do
    add_doc(view.doc)
    if (view.doc and seen[view.doc]) or matches(view.filename) then
      table.insert(views, view)
    end
  end

  return docs, views
end


local function refresh()
  core.request_project_scan()
  core.redraw = true
end


function fileops.create(directory, name)
  local path = child_path(directory, name)
  -- Friendly error; system.create_file must still use exclusive "wx".
  assert(not system.get_file_info(path), "A file or directory with that name already exists")
  assert(system.create_file(path))
  refresh()
  return path
end


function fileops.rename(filename, name)
  local old = existing_file(filename)
  local path = child_path(parent_path(old), name)
  if path == old then return old end

  -- Permit case-only rename attempts on case-insensitive filesystems.
  -- SDL_RenamePath replaces existing destinations, so the existence check
  -- is user-friendly but cannot prevent a concurrent replacement race.
  if not system.same_path(old, path) then
    assert(not system.get_file_info(path), "A file or directory with that name already exists")
  end

  local docs, views = references(old)
  assert(system.rename_file(old, path))

  for _, doc in ipairs(docs) do doc:set_filename(path) end
  for _, view in ipairs(views) do
    if view.filename then view.filename = path end
    view.lsp_link = nil
  end

  refresh()
  return path
end


-- The caller must obtain confirmation first. Keep text buffers open as
-- unsaved documents so Delete cannot discard edits or silently recreate
-- the old file on the next Save. Close read-only previews.
function fileops.delete(filename)
  local path = existing_file(filename)
  local docs, views = references(path)
  assert(system.remove_file(path))

  for _, doc in ipairs(docs) do
    doc:set_filename(nil)
    doc.clean_change_id = nil
  end

  for _, view in ipairs(views) do
    view.lsp_link = nil
    if not view.doc then
      local root = core.root_view.root_node
      local node = root:get_node_for_view(view)
      if node then node:close_view(root, view) end
    end
  end

  refresh()
end


return fileops
