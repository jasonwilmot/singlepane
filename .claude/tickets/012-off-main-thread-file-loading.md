# 012: Off-Main-Thread File Loading for Preview

**Priority:** P2
**Effort:** Medium
**Labels:** Improvement, Preview
**Phase:** 2 — Differentiator

## Problem

`PreviewContainerViewController.filePanelDidSelect(fileURL:)` loads files synchronously on the main thread. Selecting a large file freezes the entire UI until the file is read, parsed, and rendered. CLAUDE.md § 4.2 mandates: "The main thread does nothing except render UI and handle input events."

## Requirements

### Async Loading
- File reading happens on a background actor/task
- UI shows a lightweight placeholder immediately on selection
- Content replaces placeholder when loading completes
- If a new file is selected before the previous load completes, cancel the previous load

### Progress Indication
- Files that load in < 200ms: no indicator (instant feel)
- Files that take > 200ms: show a subtle loading state (not a spinner — a progress bar or shimmer)
- Never show a blank white/black rectangle while loading

### Cancellation
- Rapid file selection (clicking through file list quickly) should not queue up loads
- Only the most recent selection's load should complete
- Use Swift structured concurrency `Task` with cancellation checks

### Error Handling
- If file is unreadable (permissions, corruption), show error message in preview area
- If encoding detection fails, show raw bytes or offer encoding picker

## Implementation Notes

- Wrap file loading in `Task { }` with `try Task.checkCancellation()` at key points
- Store the current loading `Task` and call `.cancel()` when a new file is selected
- For `CodePreviewViewController`: load file → highlight → apply attributed string, all on background, then hop to main for display
- For `MarkdownPreviewViewController`: load file → parse markdown → generate HTML on background, then `loadHTMLString` on main
- Consider an `AsyncSequence`-based pipeline: `fileSelected → load → transform → render`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — async file routing
- `totalcommander/UI/Preview/CodePreviewViewController.swift` — async loadFile
- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — async loadMarkdownFile
- `totalcommander/UI/Preview/EditorViewController.swift` — async loadFile

## Acceptance Criteria

- [ ] Selecting a 10MB file does not freeze the UI
- [ ] Rapidly clicking through 20 files shows only the last selected file's content
- [ ] Files < 200ms to load show no loading indicator
- [ ] Files > 200ms show a subtle loading state
- [ ] Unreadable files show a clear error message
- [ ] Main thread stays responsive (verified via Instruments)
