local syntax = require "core.syntax"

syntax.add {
  files = { "[Mm]akefile$", "GNUmakefile$", "%.mk$", "%.mak$" },
  comment = "#",
  patterns = {
    { pattern = [=[\$[@<?^*+%]]=],        type = "keyword2" },
    { pattern = { [=[\$\(]=], [=[\)]=] }, type = "keyword2" },
    { pattern = { [=[\$\{]=], [=[\}]=] }, type = "keyword2" },
    { pattern = "#.*",                     type = "comment" },
    { pattern = [=[[A-Za-z_][A-Za-z0-9_]*\s*[:+?]?=]=], type = "keyword2" },
    { pattern = [=[[A-Za-z0-9_.\-/]+\s*:]=], type = "function" },
    { pattern = [=[[+\-=/\*^%<>!~|&:]]=], type = "operator" },
    { pattern = [=[\d+\.?\d*]=],          type = "number" },
    { pattern = [=[-?[A-Za-z_][A-Za-z0-9_-]*]=], type = "symbol" },
  },
  symbols = {
    ["include"] = "keyword", ["-include"] = "keyword", ["sinclude"] = "keyword",
    ["define"] = "keyword", ["endef"] = "keyword", ["override"] = "keyword",
    ["export"] = "keyword", ["unexport"] = "keyword", ["private"] = "keyword",
    ["ifdef"] = "keyword", ["ifndef"] = "keyword", ["ifeq"] = "keyword",
    ["ifneq"] = "keyword", ["else"] = "keyword", ["endif"] = "keyword",
    ["foreach"] = "function", ["if"] = "function", ["call"] = "function",
    ["eval"] = "function", ["shell"] = "function", ["wildcard"] = "function",
    ["patsubst"] = "function", ["subst"] = "function", ["strip"] = "function",
    ["filter"] = "function", ["filter-out"] = "function", ["findstring"] = "function",
    ["sort"] = "function", ["word"] = "function", ["words"] = "function",
    ["wordlist"] = "function", ["firstword"] = "function", ["lastword"] = "function",
    ["dir"] = "function", ["notdir"] = "function", ["basename"] = "function",
    ["suffix"] = "function", ["addprefix"] = "function", ["addsuffix"] = "function",
    ["join"] = "function", ["origin"] = "function", ["flavor"] = "function",
    ["value"] = "function", ["abspath"] = "function", ["realpath"] = "function",
  },
}
