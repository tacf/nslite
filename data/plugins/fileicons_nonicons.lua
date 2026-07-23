-- Nonicons file-type icons for the project tree.
--
-- The font is from https://github.com/yamatsum/nonicons and is distributed
-- under the MIT license in data/fonts/nonicons.LICENSE.txt.

local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local TreeView = require "plugins.treeview"


config.file_icons = config.file_icons or {}
if config.file_icons.enabled == nil then
  config.file_icons.enabled = true
end
if config.file_icons.colorize == nil then
  config.file_icons.colorize = true
end


local icon_font = renderer.font.load(
  EXEDIR .. "/data/fonts/nonicons.ttf",
  15 * SCALE
)

local function icon(codepoint, color)
  return {
    glyph = utf8.char(codepoint),
    color = color and { common.color(color) } or nil,
  }
end


local icons = {
  archive    = icon(61699, "#d0bf41"),
  book       = icon(61711, "#72b886"),
  c          = icon(61718, "#599eff"),
  cpp        = icon(61719, "#519aba"),
  csharp     = icon(61720, "#596706"),
  code       = icon(61734, "#6d8086"),
  css        = icon(61743, "#563d7c"),
  database   = icon(61746, "#dad8d8"),
  diff       = icon(61770, "#657175"),
  docker     = icon(61758, "#4289a1"),
  elixir     = icon(61971, "#a074c4"),
  elm        = icon(61763, "#519aba"),
  file       = icon(61766),
  license    = icon(61767, "#d0bf41"),
  binary     = icon(61768, "#cc3e55"),
  folder     = icon(62011),
  folder_open = icon(62012),
  gear       = icon(61781, "#6d8086"),
  go         = icon(61789, "#519aba"),
  header     = icon(61792, "#599eff"),
  history    = icon(61795, "#657175"),
  html       = icon(61799, "#e34c26"),
  image      = icon(61801, "#a074c4"),
  java       = icon(61809, "#cc3e44"),
  javascript = icon(61810, "#cbcb41"),
  json       = icon(61811, "#854cc7"),
  key        = icon(61813, "#d0bf41"),
  kotlin     = icon(61814, "#f88a02"),
  lua        = icon(61826, "#51a0cf"),
  markdown   = icon(61829, "#519aba"),
  package    = icon(61846, "#d0bf41"),
  perl       = icon(61853, "#519aba"),
  php        = icon(61855, "#a074c4"),
  python     = icon(61863, "#3572a5"),
  r          = icon(61866, "#358a5b"),
  rss        = icon(61879, "#cc3e44"),
  ruby       = icon(61880, "#701516"),
  rust       = icon(61881, "#dea584"),
  scala      = icon(61882, "#cc3e44"),
  swift      = icon(61906, "#e37933"),
  terminal   = icon(61911, "#4d5a5e"),
  toml       = icon(61916, "#6d8086"),
  typescript = icon(61923, "#519aba"),
  video      = icon(61951, "#e85e00"),
  vim        = icon(61932, "#8f00ff"),
  yaml       = icon(61945, "#6d8086"),
  zip        = icon(61775, "#d0bf41"),
}


local extension_icons = {
  [".7z"] = icons.archive,
  [".a"] = icons.binary,
  [".app"] = icons.binary,
  [".asm"] = icons.code,
  [".avi"] = icons.video,
  [".bash"] = icons.terminal,
  [".bat"] = icons.terminal,
  [".bin"] = icons.binary,
  [".bmp"] = icons.image,
  [".bz2"] = icons.archive,
  [".c"] = icons.c,
  [".cc"] = icons.cpp,
  [".cfg"] = icons.gear,
  [".cjs"] = icons.javascript,
  [".cmake"] = icons.gear,
  [".conf"] = icons.gear,
  [".cpp"] = icons.cpp,
  [".cs"] = icons.csharp,
  [".css"] = icons.css,
  [".csv"] = icons.database,
  [".cxx"] = icons.cpp,
  [".d.ts"] = icons.typescript,
  [".db"] = icons.database,
  [".desktop"] = icons.gear,
  [".diff"] = icons.diff,
  [".dll"] = icons.binary,
  [".dylib"] = icons.binary,
  [".ejs"] = icons.html,
  [".elm"] = icons.elm,
  [".ex"] = icons.elixir,
  [".exs"] = icons.elixir,
  [".exe"] = icons.binary,
  [".fish"] = icons.terminal,
  [".gif"] = icons.image,
  [".go"] = icons.go,
  [".gz"] = icons.archive,
  [".h"] = icons.header,
  [".hh"] = icons.header,
  [".hpp"] = icons.header,
  [".htm"] = icons.html,
  [".html"] = icons.html,
  [".hxx"] = icons.header,
  [".ico"] = icons.image,
  [".ini"] = icons.gear,
  [".jar"] = icons.package,
  [".java"] = icons.java,
  [".jpeg"] = icons.image,
  [".jpg"] = icons.image,
  [".js"] = icons.javascript,
  [".json"] = icons.json,
  [".jsonc"] = icons.json,
  [".jsx"] = icons.javascript,
  [".kt"] = icons.kotlin,
  [".kts"] = icons.kotlin,
  [".lock"] = icons.key,
  [".lua"] = icons.lua,
  [".m4a"] = icons.video,
  [".make"] = icons.terminal,
  [".markdown"] = icons.markdown,
  [".md"] = icons.markdown,
  [".mjs"] = icons.javascript,
  [".mkv"] = icons.video,
  [".mov"] = icons.video,
  [".mp3"] = icons.video,
  [".mp4"] = icons.video,
  [".o"] = icons.binary,
  [".obj"] = icons.binary,
  [".otf"] = icons.binary,
  [".patch"] = icons.diff,
  [".pdf"] = icons.book,
  [".php"] = icons.php,
  [".pl"] = icons.perl,
  [".pm"] = icons.perl,
  [".png"] = icons.image,
  [".ps1"] = icons.terminal,
  [".py"] = icons.python,
  [".pyc"] = icons.python,
  [".pyd"] = icons.python,
  [".r"] = icons.r,
  [".rar"] = icons.archive,
  [".rb"] = icons.ruby,
  [".rs"] = icons.rust,
  [".rss"] = icons.rss,
  [".sass"] = icons.css,
  [".scala"] = icons.scala,
  [".scss"] = icons.css,
  [".sh"] = icons.terminal,
  [".so"] = icons.binary,
  [".sql"] = icons.database,
  [".svg"] = icons.image,
  [".swift"] = icons.swift,
  [".tar"] = icons.archive,
  [".tgz"] = icons.archive,
  [".toml"] = icons.toml,
  [".ts"] = icons.typescript,
  [".tsx"] = icons.typescript,
  [".ttf"] = icons.binary,
  [".vim"] = icons.vim,
  [".wasm"] = icons.binary,
  [".webp"] = icons.image,
  [".xml"] = icons.html,
  [".xz"] = icons.archive,
  [".yaml"] = icons.yaml,
  [".yml"] = icons.yaml,
  [".zig"] = icons.code,
  [".zip"] = icons.zip,
  [".zsh"] = icons.terminal,
}


local filename_icons = {
  [".babelrc"] = icons.javascript,
  [".gitignore"] = icons.diff,
  [".gitmodules"] = icons.diff,
  [".npmrc"] = icons.package,
  ["changelog"] = icons.history,
  ["changelog.md"] = icons.history,
  ["changelog.txt"] = icons.history,
  ["cmakelists.txt"] = icons.gear,
  ["copying"] = icons.license,
  ["docker-compose.yaml"] = icons.docker,
  ["docker-compose.yml"] = icons.docker,
  ["dockerfile"] = icons.docker,
  ["license"] = icons.license,
  ["license.md"] = icons.license,
  ["license.txt"] = icons.license,
  ["makefile"] = icons.terminal,
  ["package-lock.json"] = icons.package,
  ["package.json"] = icons.package,
  ["readme"] = icons.book,
  ["readme.md"] = icons.book,
  ["readme.txt"] = icons.book,
}


local function find_extension_icon(filename)
  local dot = filename:find(".", 1, true)
  while dot do
    local match = extension_icons[filename:sub(dot)]
    if match then
      return match
    end
    dot = filename:find(".", dot + 1, true)
  end
end


local default_get_item_icon = TreeView.get_item_icon

function TreeView:get_item_icon(item, active, hovered)
  if not config.file_icons.enabled then
    return default_get_item_icon(self, item, active, hovered)
  end

  local selected
  if item.type == "dir" then
    selected = item.expanded and icons.folder_open or icons.folder
  else
    local name = item.name:lower()
    selected = filename_icons[name] or find_extension_icon(name) or icons.file
  end

  local color = style.text
  if config.file_icons.colorize and selected.color then
    color = selected.color
  end
  if active or hovered then
    color = style.accent
  end

  return selected.glyph, icon_font, color
end


return {
  font = icon_font,
  icons = icons,
  extension_icons = extension_icons,
  filename_icons = filename_icons,
}
