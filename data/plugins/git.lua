local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

config.git_log_limit = config.git_log_limit or 500

-- Surely, these are enough colors. Right?
local GRAPH_PALETTE = {
  { common.color "#e58ac9" },
  { common.color "#93ddfa" },
  { common.color "#f7c95c" },
  { common.color "#ffa94d" },
  { common.color "#7dcfff" },
  { common.color "#9ae6b4" },
  { common.color "#f77483" },
}

local COL_W = common.round(14 * SCALE)
local DOT = common.round(6 * SCALE)
local LINE = math.max(1, common.round(2 * SCALE))


local function relative_time(t, now)
  local diff = now - t
  if diff < 0 then diff = 0 end
  if diff < 60 then return "now" end
  if diff < 3600 then return string.format("%dm ago", diff // 60) end
  if diff < 86400 then return string.format("%dh ago", diff // 3600) end
  if diff < 86400 * 30 then return string.format("%dd ago", diff // 86400) end
  if diff < 86400 * 365 then
    return string.format("%dmo ago", diff // (86400 * 30))
  end
  return string.format("%dy ago", diff // (86400 * 365))
end


local function display_ref(name)
  if name == "HEAD" then return "HEAD" end
  if name:find("^refs/heads/") then return name:sub(12) end
  if name:find("^refs/tags/") then return "tag: " .. name:sub(11) end
  if name:find("^refs/remotes/") then return name:sub(14) end
  return name
end


-- cropping measures the font per char dropped, so cache it per row
local function cropped_summary(row, font, max_w)
  if row.crop_font ~= font or row.crop_w ~= max_w then
    row.crop_font, row.crop_w = font, max_w
    row.crop_text = common.crop_text(font, row.commit.summary, max_w)
  end
  return row.crop_text
end


local TOP, MID, BOT = 0.0, 0.5, 1.0


local function build_graph(commits)
  local rows = {}
  local lanes = {}        -- lanes[col] = oid of the active lane
  local lane_color = {}   -- lane_color[col] = palette index
  local oid_col = {}      -- oid -> column of its active lane
  local color_seq = 0

  local function next_color()
    color_seq = color_seq + 1
    return ((color_seq - 1) % #GRAPH_PALETTE) + 1
  end

  for _, commit in ipairs(commits) do
    local oid = commit.oid
    local parents = commit.parents

    local own_col = oid_col[oid]
    local fresh = false
    if not (own_col and lanes[own_col] == oid) then
      own_col = #lanes + 1
      lanes[own_col] = oid
      lane_color[own_col] = next_color()
      oid_col[oid] = own_col
      fresh = true
    end
    local own_color = lane_color[own_col]

    local parent_cols = {}
    for i, p in ipairs(parents) do
      parent_cols[i] = oid_col[p]
    end

    local next_lanes = {}
    local next_color_of = {}
    for k, o in ipairs(lanes) do
      if k ~= own_col then
        next_lanes[#next_lanes + 1] = o
        next_color_of[#next_color_of + 1] = lane_color[k]
      end
    end

    for i, p in ipairs(parents) do
      if not parent_cols[i] then
        local ncol
        if i == 1 then
          ncol = own_col
        else
          local base = parent_cols[1] or own_col
          ncol = math.min(base + 1, #next_lanes + 1)
        end
        table.insert(next_lanes, ncol, p)
        table.insert(next_color_of, ncol, i == 1 and own_color or next_color())
        oid_col[p] = ncol
        parent_cols[i] = ncol
      end
    end

    local next_index = {}
    for nk, no in ipairs(next_lanes) do
      if next_index[no] == nil then next_index[no] = nk end
    end

    local new_col = {}
    for k, o in ipairs(lanes) do
      if k ~= own_col then
        new_col[k] = next_index[o]
        oid_col[o] = new_col[k]
      end
    end
    oid_col[oid] = nil

    local lines = {}
    local conns = {}
    local function add_line(col, color, y0, y1)
      lines[#lines + 1] = { col, color, y0, y1 }
    end
    local function add_conn(a, b, color)
      if a == b then return end
      for _, c in ipairs(conns) do
        if c[1] == a and c[2] == b then return end
      end
      conns[#conns + 1] = { a, b, color }
    end

    local recolor_col = nil
    if parents[1] and parent_cols[1] and parent_cols[1] ~= own_col
      and parent_cols[1] > own_col then
      recolor_col = parent_cols[1]
    end

    for k, o in ipairs(lanes) do
      if k ~= own_col then
        local nk = new_col[k]
        local c = lane_color[k]
        if k == recolor_col then
          if nk == k then
            add_line(k, c, TOP, BOT)
            next_color_of[k] = own_color
          else
            add_line(k, c, TOP, MID)
            add_line(nk, own_color, MID, BOT)
            add_conn(k, nk, own_color)
            next_color_of[nk] = own_color
          end
        elseif nk == k then
          add_line(k, c, TOP, BOT)
        else
          add_line(k, c, TOP, MID)
          add_line(nk, c, MID, BOT)
          add_conn(k, nk, c)
        end
      end
    end

    local own_cont = parents[1] ~= nil and parent_cols[1] == own_col
    local own_y0 = fresh and MID or TOP
    local own_y1 = own_cont and BOT or MID
    if own_y0 ~= own_y1 then
      add_line(own_col, own_color, own_y0, own_y1)
    end

    local used = {}
    for _, nk in pairs(new_col) do used[nk] = true end
    used[own_col] = true
    for nk = 1, #next_lanes do
      if not used[nk] then
        add_line(nk, next_color_of[nk], MID, BOT)
      end
    end

    for i, pc in ipairs(parent_cols) do
      if pc then add_conn(own_col, pc, own_color) end
    end

    local refs_text
    if commit.refs then
      for i, name in ipairs(commit.refs) do
        refs_text = i > 1 and (refs_text .. ", " .. display_ref(name))
          or display_ref(name)
      end
    end

    rows[#rows + 1] = {
      commit = commit,
      own_col = own_col,
      own_color = own_color,
      lines = lines,
      conns = conns,
      ncols = math.max(#lanes, #next_lanes),
      refs_text = refs_text,
    }

    lanes = next_lanes
    lane_color = next_color_of
  end
  return rows
end


local GitView = View:extend()


function GitView:new()
  GitView.super.new(self)
  self.scrollable = true
  self.error = nil
  self.commits = {}
  self.rows = {}
  self.ncols = 1
  self.repo_path = core.project_dir
  self:update_metrics()
  self:load()
end


function GitView:get_name()
  return "Git Log"
end


function GitView:get_scrollable_size()
  return self.total_size
end


function GitView:load()
  self.error = nil
  self.rows = {}
  self.repo = nil
  self:update_metrics()

  local repo, err = git.open(self.repo_path)
  if not repo then
    self.error = err or "Could not open repository"
    return
  end
  self.repo = repo

  local commits, log_err = repo:log(config.git_log_limit)
  if not commits then
    self.error = log_err or "Could not read repository history"
    return
  end

  self.commits = commits
  self.rows = build_graph(commits)
  self.ncols = 1
  for _, row in ipairs(self.rows) do
    self.ncols = math.max(self.ncols, row.ncols)
  end
  self:update_metrics()
end


function GitView:update_metrics()
  self.row_height = style.font:get_height() + style.padding.y
  self.total_size = style.padding.y + #self.rows * self.row_height
end


function GitView:update()
  self:update_metrics()
  GitView.super.update(self)
end


function GitView:draw_centered(text, y)
  local tw = style.font:get_width(text)
  local x = self.position.x + (self.size.x - tw) / 2
  local th = style.font:get_height()
  renderer.draw_text(style.font, text, x, y + (self.size.y - th) / 2, style.dim)
end


function GitView:draw()
  self:draw_background(style.background)

  if self.error then
    self:draw_centered(self.error, 0)
    return
  end

  if #self.rows == 0 then
    self:draw_centered("No commits yet", 0)
    return
  end

  local ox, oy = self:get_content_offset()
  local font = style.font
  local th = font:get_height()
  local row_h = self.row_height
  local x0 = ox + style.padding.x
  local top = oy + style.padding.y

  local time_x = self.position.x + self.size.x - style.padding.x
  local text_x = x0 + self.ncols * COL_W + style.padding.x
  local now = os.time()

  -- only draw the rows intersecting the viewport
  local first = math.max(1, math.floor((self.position.y - top) / row_h) + 1)
  local last = math.min(#self.rows,
    math.ceil((self.position.y + self.size.y - top) / row_h))

  local y = top + (first - 1) * row_h

  for i = first, last do
    local row = self.rows[i]
    local commit = row.commit
    local dot_y = common.round(y + row_h / 2)

    for _, seg in ipairs(row.lines) do
      local col, color, y0, y1 = seg[1], seg[2], seg[3], seg[4]
      local cx = x0 + (col - 1) * COL_W + COL_W / 2
      local c = GRAPH_PALETTE[color] or style.dim
      local p0 = math.floor(y + row_h * y0)
      local p1 = math.floor(y + row_h * y1)
      renderer.draw_rect(cx - LINE / 2, p0, LINE, p1 - p0, c)
    end

    for _, j in ipairs(row.conns) do
      local a, b, color = j[1], j[2], j[3]
      local xa = x0 + (a - 1) * COL_W + COL_W / 2
      local xb = x0 + (b - 1) * COL_W + COL_W / 2
      local c = GRAPH_PALETTE[color] or style.dim
      renderer.draw_rect(math.min(xa, xb) - LINE / 2, dot_y - LINE / 2,
        math.abs(xb - xa) + LINE, LINE, c)
    end

    local cx = x0 + (row.own_col - 1) * COL_W + COL_W / 2
    renderer.draw_rect(cx - DOT / 2, dot_y - DOT / 2, DOT, DOT,
      GRAPH_PALETTE[row.own_color] or style.text)

    local tx = text_x
    local ty = y + (row_h - th) / 2

    if row.refs_text then
      renderer.draw_text(font, row.refs_text, tx, ty, style.accent)
      tx = tx + font:get_width(row.refs_text) + style.padding.x
    end

    renderer.draw_text(font, commit.short, tx, ty, style.dim)
    tx = tx + font:get_width(commit.short) + style.padding.x

    local time_text = relative_time(commit.author_time, now)
    local time_w = font:get_width(time_text)
    local summary_max = time_x - time_w - style.padding.x - tx
    local summary = cropped_summary(row, font, summary_max)
    if summary ~= "" then
      renderer.draw_text(font, summary, tx, ty, style.text)
    end

    renderer.draw_text(font, time_text, time_x - time_w, ty, style.dim)

    y = y + row_h
  end

  self:draw_scrollbar()
end


command.add(nil, {
  ["git:log"] = function()
    core.root_view:open_view(GitView(), function(existing)
      return existing:is(GitView)
    end)
  end,

  ["git:reload"] = function()
    for _, view in ipairs(core.root_view.root_node:get_children()) do
      if view:is(GitView) then
        view:load()
      end
    end
  end,
})

keymap.add { ["mod+shift+g"] = "git:log" }

return GitView
