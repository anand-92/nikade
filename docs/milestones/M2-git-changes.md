# M2: Git Changes Management

## Goals

Implement the Git changes panel, supporting status viewing, Stage/Unstage, commit, and Diff viewing.

## Tasks

### T2.1 Git Service ✅
- [x] GitService.swift — Process wrapper calling git CLI
- [x] git status parsing (`--porcelain=v1 --branch`)
- [x] git diff retrieval (staged / unstaged / untracked)
- [x] git add / restore --staged / commit / checkout

### T2.2 Changes Panel ✅
- [x] SwiftUI List showing Staged / Modified / Untracked groups
- [x] Single file Stage/Unstage buttons
- [x] Stage All / Unstage All
- [x] Commit message textarea + Cmd+Enter commit

### T2.3 Diff View ✅
- [x] Unified diff rendering (monospace + line coloring)
- [x] Green added lines / Red removed lines highlighting
- [x] File header info display (selected file path)
- [x] File content syntax highlighting (lightweight keywords/comments/strings)

### T2.4 File Watcher ✅
- [x] `FSEvents` monitoring working directory changes
- [x] Debounce (300ms) auto-refresh git status
- [x] Ignore `.git/`, `node_modules/`, etc.

### T2.5 Branches and Remote Operations ✅
- [x] ahead/behind display
- [x] Create branch and switch
- [x] Delete branch (Normal delete / Force delete)
- [x] Fetch / Pull / Push operation entry

### T2.6 Discard Changes ✅
- [x] Single file Discard (modified/untracked)
- [x] Discard All (modified + untracked)
- [x] Confirmation popup before execution

## Implementation Notes

- Added `GitService`:
  - `status/stage/unstage/stageAll/unstageAll/commit/diff/branches/checkout`
  - `createBranch/deleteBranch/fetch/pull/push/discardModified/discardUntracked`
  - Supports porcelain v1 status parsing and branch info reading
  - Supports upstream + ahead/behind parsing
- Added `GitChangesStore`:
  - Repository selection, status refresh, file selection diff, commit auto-stage
  - Branch creation/deletion and remote operation orchestration, discard command orchestration
  - Combined with `FileWatcher` for directory change auto-refresh (ignoring `.git/`, `node_modules/`)
- Added `GitChangesView`:
  - Left side changes group list + operation buttons (including Discard/Discard All)
  - Right side unified diff view
  - In-line syntax highlighting for diff (matching keywords/comments/strings by file extension)
  - Bottom commit input area (Cmd+Enter)
  - Header added branch/remote operations and tracking info
- Added `AppNavigationStore` + sidebar selection:
  - Switching between Terminal and Git Changes panels
  - Terminal shortcuts active only when Terminal panel is active

## Verification

- [x] `xcodebuild -scheme openOwl -configuration Debug build` passed
- [ ] Runtime manual test pending:
  - Status refresh after selecting repo
  - Stage/Unstage/Commit behavior
  - Branch create/delete/checkout + ahead/behind display
  - Fetch/Pull/Push
  - Watcher triggers auto-refresh

## Completion Criteria

- [x] Sidebar can enter Git Changes panel
- [x] Can Stage/Unstage files and commit
- [x] Can view file diff
- [ ] All runtime manual test matrix items passed
