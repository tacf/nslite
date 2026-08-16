# Changelog

## v1.6.2/3

### Fixed

- Second and third time is the charm, build fixed!
- Regression: missing tab close button (most likely from 1.5.x)

## v1.6.1

### Fixed

- Click detection in tree view introduced in 1.5.2, and clearly not fixed by 1.6.0
- Fix build? For real this time?! I can't cMake !

## v1.6.0

### Added

- Git log view

### Fixed

- Click detection in tree view introduced in 1.5.2
- 1.5.2 unable to be installed via brew due to committing changes from experimental git view branch

## v1.5.2

### Fixed

- Tree View scrolling now only triggers enabled when needed

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
