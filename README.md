# nslite - Not So Lite

Text editor based on [rxi/lite](https://github.com/rxi/lite).

- The editor is mainly a rendering engine built in C and constructed through the supplied Lua API.
- SDL3 is used as the rendering library.
- Lua 5.5 is the base Lua version.

Features:

- Modern styled command prompt
- Modern styled search in document
- C-native document management (for increased performance -- improvements to come)
- C-native PCRE2 tokenizer with document-owned token caching
- Native LSP integration (basic functionality only - 'click to go to')
- Built-in TTF and OTF font previews

## `Document` API

Document contents, filenames, line endings, file I/O, position traversal, and
text edits are owned by the C `document` module. The Lua `Doc` class remains the
editor-facing facade for selections, undo grouping, syntax highlighting, and
commands.

## Native tokenizer

Language plugins define syntax using PCRE2 patterns and symbol mappings in Lua.
The C `document` module compiles those definitions and tokenizes document lines
directly, while owning multiline state, token caches, and edit invalidation.
Lua only selects and configures the syntax and iterates over the resulting
tokens for rendering.

## Language servers

Native LSP support provides mod-click definition navigation. Holding `Ctrl`, or
`Command` on macOS, highlights definitions like links when a language server
can resolve them; clicking jumps to the target. The status bar shows the
configured server for the active document type.

The C `lsp` module owns server communication and document synchronization,
while Lua selects and configures language servers. `clangd` is enabled for C
and C++, and `gopls` for Go; both start lazily when needed.

## Presentations

This is one drift from the original implementation. Alongside the move of most
core logic into native C (like document handling). We're extending the DocView
with a couple of so called `presentations`, which are basically just different
views for different purposes.

These "specialized" views live under `core.presentations` and on opening a file
the `core.filepresentation` selects the proper view to use. Plugins can register
additional filename patterns and open functions with `filepresentation.add`;
registrations define the order of priority -- last registered being the top one.

### Font View

Opening a TTF or OTF font displays a scrollable text samples at several sizes.
The shown glyphs are based on hardcoded strings defined in the plugin lua code,
so they may not match exactly what you'd expect to see (you can check the icons
font file used by this editor that is present in the main data/ folder as an
example of this).

## Development

### CMake

CMake 3.20 or newer is the underlying build system. Configure and build a debug
version with:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

Use `Release` instead of `Debug` for an optimized build. Some project
dependencies are downloaded by CMake when the build directory is first
configured.

### Make

The Makefile provides shortcuts for the common CMake commands:

```sh
make          # debug build
make release  # release build
make run      # debug build, then run the editor
make clean    # remove the build directory
```

## License

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
