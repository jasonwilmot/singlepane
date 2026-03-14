# 014: Split Preview (Side-by-Side Source + Rendered)

**Priority:** P3
**Effort:** Medium
**Labels:** Feature, Preview
**Phase:** 2 — Differentiator

## Problem

VS Code's Cmd+K V split preview (source on left, rendered output on right) is a staple for developers editing markdown, HTML, and other renderable formats. Our current tab-based switching between Preview/Editor modes requires full context switches. Power users want to see both simultaneously.

## Requirements

### Split Mode
- New layout option: source editor on one side, rendered preview on the other
- Available for markdown (source + rendered HTML) and HTML (source + rendered page)
- Horizontal split (left/right) by default, vertical split (top/bottom) as option
- Draggable divider to adjust split ratio
- Keyboard shortcut to toggle split mode

### Synchronized Scrolling
- Scrolling the source scrolls the preview to the corresponding section (and vice versa)
- Sync should be approximate (heading-based for markdown, line-based for code)
- Option to disable sync scroll

### Cursor Tracking
- Editing in the source highlights/scrolls to the corresponding section in preview
- Clicking in the preview scrolls to the corresponding source line (if possible with WKWebView)

## Implementation Notes

- Use `NSSplitView` within the preview container content area
- Left/top: `EditorViewController` (or `CodePreviewViewController` for read-only)
- Right/bottom: `MarkdownPreviewViewController` (or `BrowserViewController` for HTML)
- Sync scroll: for markdown, build a line-to-heading mapping. When source scrolls past a heading line, scroll preview to that heading's HTML anchor
- WKWebView scroll position can be set via JavaScript: `document.getElementById('heading-3').scrollIntoView()`
- Add heading IDs to generated HTML in `MarkdownPreviewViewController` (e.g., `<h2 id="heading-2">`)

## Files to Create

- `totalcommander/UI/Preview/SplitPreviewViewController.swift`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — add split mode toggle
- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — add heading anchors to HTML, expose scroll-to-heading API

## Acceptance Criteria

- [ ] Split mode shows source and preview side by side
- [ ] Works for markdown files
- [ ] Works for HTML files
- [ ] Divider is draggable
- [ ] Scroll sync: scrolling source scrolls preview approximately
- [ ] Keyboard shortcut toggles split mode
- [ ] Exiting split mode returns to the previously active tab (preview or editor)
- [ ] Theme-aware divider styling
