# 007: Find Bar in Code Preview

**Priority:** P2
**Effort:** Small
**Labels:** Feature, Preview
**Phase:** 1 — Must-Have

## Problem

`EditorViewController` has `usesFindBar = true` but `CodePreviewViewController` (the read-only code viewer) does not expose a find bar. Users expect Cmd+F to work in any text-displaying view. Currently pressing Cmd+F in code preview does nothing.

## Requirements

- Enable the NSTextView find bar in `CodePreviewViewController`
- Cmd+F activates the find bar
- Support find next (Cmd+G), find previous (Cmd+Shift+G)
- Match highlighting should use theme accent color
- Find bar should respect the current theme styling

## Implementation Notes

- This is likely a one-line fix: set `usesFindBar = true` and `isIncrementalSearchingEnabled = true` on the NSTextView
- May also need to ensure the text view's `isSelectable = true` (should already be the case for read-only)
- Ensure the enclosing NSScrollView's `isFindBarVisible` property is accessible

## Files to Modify

- `totalcommander/UI/Preview/CodePreviewViewController.swift`

## Acceptance Criteria

- [ ] Cmd+F opens find bar in code preview
- [ ] Find next / find previous work
- [ ] Matches are highlighted
- [ ] Escape dismisses the find bar
- [ ] Find bar inherits theme styling (not jarring white bar on dark theme)
