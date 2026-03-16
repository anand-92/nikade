# Postmortem: Terminal Copy/Paste Not Working

**Date**: 2026-03-16
**Severity**: P1 (core functionality broken)
**Resolution time**: ~1 hour iterative debugging

## Summary

Terminal copy (Cmd+C) and paste (Cmd+V) were completely non-functional. Root cause was a combination of three issues in the `performKeyEquivalent` event routing.

## Root Causes

### 1. Wrong pane receives paste (primary cause)

Multiple `TerminalNSView` instances exist (splits, tabs). `performKeyEquivalent` traverses the entire NSView hierarchy depth-first. The **first** TerminalNSView to return `true` consumes the event — but this was often a **hidden** pane (inactive tab with `opacity(0)` or wrong split pane).

**Fix**: Guard with `surface == appManager?.activeSurface && isEffectivelyVisible`.

### 2. `ghostty_surface_binding_action` length parameter was 0

```swift
// Before (broken):
ghostty_surface_binding_action(surface, "copy_to_clipboard", 0)

// After (fixed):
ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
```

Third parameter is the action string's byte length. Passing `0` caused ghostty to match nothing.

### 3. Edit menu stealing events from non-terminal views

When user was on Deployment/Git tab, the hidden terminal views' `performKeyEquivalent` still intercepted Cmd+V/C, preventing TextFields from receiving paste.

**Fix**: `isEffectivelyVisible` check walks the superview chain for `alphaValue < 0.01`, which SwiftUI sets via `.opacity(0)`.

## Failed Approaches

| Approach | Result |
|---|---|
| `ghostty_surface_binding_action("paste_from_clipboard")` | Crash — `read_clipboard_cb` async defer invalidates `state` pointer |
| `makeFirstResponder` in `performKeyEquivalent` | Terminal view destroyed — triggers `onFocus` → `workspace.focusPane` → `@Published` state change → SwiftUI re-render |

## Final Architecture

```
Cmd+V pressed
  → performKeyEquivalent traverses all NSViews
  → Each TerminalNSView checks:
      1. Is my surface the activeSurface? (correct pane)
      2. Am I effectively visible? (correct tab)
  → Only the active, visible pane handles it
  → ghostty_surface_set_focus(surface, true) — ensure surface accepts input
  → ghostty_surface_text(surface, clipboard, len) — direct PTY injection
  → return true (consume event)

Other tabs (Deployment, Git):
  → All terminal views return false
  → Event falls through to Edit menu → TextField handles normally
```

## Key Learnings

1. **`performKeyEquivalent` is NOT responder-chain-based** — it traverses the entire view hierarchy. Hidden/inactive NSViews still receive it.
2. **SwiftUI `.opacity(0)` ≠ `isHidden`** — must check `alphaValue` on ancestor views.
3. **Never call `makeFirstResponder` from `performKeyEquivalent`** in SwiftUI apps — it triggers state changes that can destroy the view.
4. **`ghostty_surface_complete_clipboard_request`'s `state` pointer** is only valid during the synchronous callback scope. Async deferral causes use-after-free.

## Files Changed

- `openOwl/Ghostty/GhosttyTerminal.swift` — `performKeyEquivalent`, `copy:`, `paste:`, `selectAll:`, `isEffectivelyVisible`
- `openOwl/Ghostty/GhosttyApp.swift` — cleaned up debug logging
