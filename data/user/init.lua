-- Put user settings here. This bundled file is used only when no external user
-- module exists at $XDG_CONFIG_HOME/nslite/init.lua (or the platform default).
-- External user modules can place themes in their own colors/ directory and
-- load them with, for example: require "colors.summer"

local keymap = require "core.keymap"
local config = require "core.config"
local style = require "core.style"

-- light theme:
-- require "user.colors.summer"

-- key binding:
-- keymap.add { ["mod+escape"] = "core:quit" }

-- language servers (clangd for C/C++ is enabled by default):
-- config.lsp.servers = {
--   {
--     command = { "rust-analyzer" },
--     languages = { { id = "rust", files = { "%.rs$" } } },
--   },
-- }
