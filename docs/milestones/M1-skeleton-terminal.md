# M1: Skeleton App + libghostty Terminal

## Goals

Build the macOS native application skeleton, integrate libghostty to achieve a usable terminal, and complete basic interactions for multi-tab/split panes.

## Tasks

### T1.1 Project Scaffold ✅
- [x] Create Xcode project (macOS App, SwiftUI lifecycle)
- [x] Configure minimum deployment target (macOS 14.0+)
- [x] Basic SwiftUI window + three-column layout (Sidebar / Content / Inspector)

### T1.2 Ghostty Integration ✅
- [x] Add Ghostty as git submodule
- [x] Configure Zig build script to compile libghostty static library
- [x] Create bridging header and import ghostty.h
- [x] Verify Swift can call ghostty C API

### T1.3 Terminal View ✅
- [x] Implement GhosttyApp.swift — ghostty_app_t lifecycle management
- [x] Implement GhosttyTerminal.swift — ghostty_surface_t wrapper
- [x] Implement TerminalView (NSView + CAMetalLayer)
- [x] Bridge to SwiftUI via NSViewRepresentable
- [x] Keyboard input → ghostty_surface_key()
- [x] Window resize → ghostty_surface_set_size()

### T1.4 Terminal Features ✅
- [x] Shell auto-detection and startup (Priority to user-configured command; fallback to shell if no command)
- [x] Read ~/.config/ghostty/config (including recursive includes)
- [x] Theme/font configuration passed to libghostty, with runtime config snapshot recorded
- [x] scrollback applied by libghostty configuration (reading `scrollback-limit` snapshot)

### T1.5 Multi-tab + Split Panes ✅
- [x] In-app Tab bar (Cmd+T/W/1-9)
- [x] Multi-level split panes (Cmd+D for horizontal split, Cmd+Shift+D for vertical split)
- [x] Split pane focus switching (Cmd+Arrow, no-op if no target at boundary)
- [x] `Cmd+W` hierarchy: Split pane > Tab > Window

### P1 Enhancements (Continuous Iteration)
- [x] Terminal title tracking (OSC 0/2 -> Tab title)
- [ ] URL detection + Cmd+Click to open links
- [ ] Runtime scrollback adjustment UI

## Implementation Notes

- Added `TerminalWorkspaceStore` to manage tabs, active tab, split tree, and focused pane.
- Added `TerminalSplitNode` recursive model and SwiftUI recursive renderer, currently fixed at 50/50 ratio (no drag resizing).
- `ContentView` changed to "Tab bar + ZStack content area", tab switching does not destroy background terminal sessions.
- `GhosttyAppManager` added:
  - `launchProfile` (`configCommand` + `fallbackShell`)
  - Pane/surface registration and per-pane focusing capability
  - Action callback forwarding `SetTitle/SetTabTitle`, driving Tab title updates
- `GhosttyConfig` added:
  - Default + recursive configuration loading
  - Diagnostics aggregation logs
  - `command/font-family/font-size/theme/scrollback-limit` snapshots

## Verification

- [x] `xcodebuild -scheme openOwl -configuration Debug build` passed
- [ ] Xcode runtime manual test (Cmd+R) pending:
  - Tab/split shortcuts and `Cmd+W` hierarchy
  - Shell fallback and user command priority
  - Theme/font/scrollback config changes effect

## Completion Criteria

- Can open the app and see an interactive terminal
- Terminal rendering quality consistent with native Ghostty
- Can run common CLI tools
- Can create multiple tabs and multi-level split panes

## References

- Ghostty macOS: `macos/Sources/`
- cmux: `github.com/manaflow-ai/cmux`
