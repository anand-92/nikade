# M3: File Explorer + Sidebar

## Goals

Implement the file explorer and project management sidebar.

## Tasks

### T3.1 File Tree
- [x] Recursive directory tree (OutlineGroup / List)
- [x] `.gitignore` filtering (via `git ls-files --ignored --exclude-standard`)
- [x] Directory first + alphabetical sorting
- [x] File icons (SF Symbols)

### T3.2 Git Status Coloring
- [x] File git status color annotation
- [x] Parent directory color propagation

### T3.3 File Interaction
- [x] Context menu (Reveal in Finder, Open in Terminal, Copy Path)
- [x] Click on changed file → Diff view
- [x] Click on regular file → Read-only preview (lightweight syntax highlighting)

### T3.4 Project Management
- [x] Project list (Top of sidebar)
- [x] Open/Switch projects (NSOpenPanel)
- [x] Project persistence (UserDefaults)

### T3.5 Preview and Search Enhancements
- [x] Quick Open (Cmd+P)
- [x] File preview syntax highlighting (keywords/comments/strings)
- [x] File drag-and-drop to terminal (path drop)

### T3.6 Status and Ignore Optimization
- [x] Fine-grained Git status mapping (A/M/D/R/U)
- [x] Ignored directory prefix compression optimization

## Implementation Notes

- Added `ProjectStore`:
  - Maintains project list and active project, supports adding/switching/deleting
  - Project list persistence to `UserDefaults`
  - Automatic injection of current working directory on first launch
- Added `FileExplorerStore` + `FileExplorerView`:
  - Recursive file tree construction, directory first + alphabetical
  - Filtering ignored paths via Git ignored list
  - File git status coloring and aggregation/propagation to parent directories (A/M/D/R/U)
  - Ignored directory prefix compression, reducing scan-match overhead for large repositories
  - Quick Open (Cmd+P) and search result positioning
  - File/directory drag-and-drop to terminal (path pasting executed by Terminal side)
  - File context menu (Reveal / Open in Terminal / Copy Path)
  - Linking changed file clicks to `GitChangesStore` to open diffs
  - Read-only preview for regular files (binary file hints, large file truncation, lightweight syntax highlighting)
- Application Layer Integration:
  - `openOwlApp` injects `ProjectStore` / `FileExplorerStore`
  - Synchronous refresh of Git panel repository and file tree context when active project changes

## Verification

- [x] `xcodegen generate`
- [x] `xcodebuild -scheme openOwl -configuration Debug -derivedDataPath /tmp/openowl-derived build`
- [ ] Runtime manual test (Xcode Cmd+R) pending:
  - File/Git context synchronization on project switch
  - Jump to Diff from changed file
  - Context menu action behavior
  - File preview and performance experience

## Completion Criteria

- [x] Sidebar can browse file tree
- [x] Files have git status colors
- [x] Can manage multiple projects
