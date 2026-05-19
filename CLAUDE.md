# AGENTS.md

## Project Overview

openOwl — macOS native Git GUI + Terminal desktop application. Built with Swift + libghostty, Metal GPU rendered terminal. No built-in AI, open terminal allows users to choose their own tools.

## Tech Stack

- Language: Swift
- UI: SwiftUI + AppKit (hybrid, terminal view uses AppKit NSView)
- Terminal: libghostty (Static library compiled with Zig, Metal rendering)
- Git: Process calls to git CLI
- File system: FileManager + DispatchSource (fs events)
- Build: Xcode + SPM

## Development Rules

1. Any code changes that are inconsistent with the documents under `docs/` must be synchronized with the corresponding documents.
2. Product decision changes (feature trade-offs, interaction adjustments, design modifications) must be written in the corresponding documents, and cannot only exist in conversations.
3. Ask me for uncertain product questions first, don't decide on your own.
4. Terminal view uses AppKit (NSView + CAMetalLayer), bridged to SwiftUI through NSViewRepresentable.
5. libghostty is imported through C bridging header, Swift calls C API directly.

## Common Commands

```bash
# Build (Command Line)
xcodebuild -scheme openOwl -configuration Debug build

# Or direct Xcode
open openOwl.xcodeproj
# Cmd+R to run
```

## Architecture

```
openOwl/
├── App/                    # SwiftUI App Entry
├── Features/
│   ├── Terminal/           # libghostty Terminal View
│   ├── Git/                # Git Changes Panel, Diff View
│   ├── FileExplorer/       # File Explorer
│   ├── RightDock/          # Right inspector panel (including Activity rail)
│   ├── Sidebar/            # Project list navigation
│   └── StatusBar/          # Bottom status bar
├── Services/
│   ├── GitService.swift    # git CLI wrapper
│   └── FileWatcher.swift   # File system monitoring
├── Ghostty/                # libghostty Swift wrapper
│   ├── GhosttyApp.swift    # ghostty_app_t lifecycle
│   ├── GhosttyTerminal.swift # ghostty_surface_t wrapper
│   └── GhosttyConfig.swift # Configuration management
└── Shared/                 # Common tools, themes, types
```

## Key References

- Ghostty macOS Source: github.com/ghostty-org/ghostty/tree/main/macos
- cmux (Third-party libghostty integration reference): github.com/manaflow-ai/cmux
- libghostty C API: include/ghostty.h in ghostty repo

## Documentation

- Project Overview → docs/PROJECT.md
- Development Progress → docs/progress.md
- Work Logs → docs/memory/
- Postmortem Records → docs/postmortem/
- Feature Documents → docs/features/
- Requirements Documents → docs/requirements/
- Milestones → docs/milestones/

## Design Guidelines

macOS native design follows global specifications: `~/.openowl/workspace/docs/strategy/macos-design-guide.md`

## Acceptance Testing

Gatekeeping process see global `~/.claude/CLAUDE.md`. E2E acceptance method for this project:
- Unit Test: XCTest (`xcodebuild -scheme openOwl -configuration Debug test`)
- E2E Acceptance: XCUITest
