# nslite - Not So Lite

Text editor based or [rxi/lite](https://github.com/rxi/lite)

- Editor is mainly a rendering engine built in C and constructed through the supplied Lua api.
- SDL3 as rendering lib
- Lua 5.5 as base lua version

Features:
- Modern styled command prompt
- Modern styled search in document
- C-Native document managment (for increased performance -- improvements to come)

## `Document` API

Document contents, filenames, line endings, file I/O, position traversal, and
text edits are owned by the C `document` module. The Lua `Doc` class remains the
editor-facing facade for selections, undo grouping, syntax highlighting, and
commands.

## License
This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
