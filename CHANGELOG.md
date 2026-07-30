# Changelog

## v1.4.1

### Fixed

- LSP workspace and document paths are canonicalized before use, preventing
  mismatches when resolving projects, references, and other server data.

## v1.4.0

### Added

- Detached startup so the terminal is released after launching the editor.

### Fixed

- Find overlay no longer overlaps the tab bar.
- Command-hover LSP navigation now triggers correctly on macOS.
- Windows build failure in the process-detachment code.
