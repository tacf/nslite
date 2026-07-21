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

## License

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
