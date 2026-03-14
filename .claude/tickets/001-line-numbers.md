# 001: Line Numbers in Code Preview & Editor

**Priority:** P1
**Effort:** Small
**Labels:** Feature, Preview
**Phase:** 1 — Must-Have

## Problem

CodePreviewViewController and EditorViewController display code without line numbers. Every competing code viewer (VS Code, Sublime, Zed, Nova, BBEdit, CotEditor) shows line numbers. This is the single most visible gap in our preview pane.

## Requirements

- Add a line number gutter to `CodePreviewViewController` (read-only view)
- Add a line number gutter to `EditorViewController` (editable view)
- Gutter should be theme-aware (use `chromeTextSecondary` for number color, subtle background)
- Gutter width should auto-size based on digit count (e.g., wider for 10,000+ line files)
- Current line should be highlighted (subtle background band across the full row)
- Line numbers must stay in sync during scroll, edit, and window resize
- Font should match `FontManager.shared.activeFont` at a slightly smaller size

## Implementation Notes

- Use `NSRulerView` subclass attached to the NSScrollView's `verticalRulerView`
- Or build a custom gutter view pinned to the leading edge of the text container
- Reference: NSTextView line number implementations are well-documented in AppKit
- Ensure line wrapping doesn't break number alignment (number corresponds to logical line, not visual line)

## Files to Modify

- `totalcommander/UI/Preview/CodePreviewViewController.swift`
- `totalcommander/UI/Preview/EditorViewController.swift`
- New: `totalcommander/UI/Preview/LineNumberGutterView.swift` (shared between both)

## Acceptance Criteria

- [ ] Line numbers visible in code preview for all file types
- [ ] Line numbers visible in editor for all file types
- [ ] Gutter auto-sizes for files with 1–999,999+ lines
- [ ] Current line highlighted in editor
- [ ] Theme changes update gutter colors immediately
- [ ] Font changes update gutter font immediately
- [ ] No scroll desync between gutter and text content
