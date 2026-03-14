# 013: Document Outline / Minimap

**Priority:** P3
**Effort:** Medium
**Labels:** Feature, Preview
**Phase:** 2 — Differentiator

## Problem

Long files are hard to navigate in preview or editor without a structural overview. Sublime Text and VS Code offer minimaps. For structured formats (markdown headings, JSON keys, code functions), an outline sidebar is more useful in a file manager context.

## Requirements

### Document Outline (Primary)
- Collapsible sidebar showing document structure:
  - **Markdown**: heading hierarchy (H1 → H2 → H3 etc.)
  - **JSON/YAML**: top-level keys (nested keys when expanded)
  - **Code files**: function/class/method names (basic regex extraction initially, Tree-sitter later)
  - **XML/HTML**: element hierarchy
- Click an outline item to scroll the preview/editor to that section
- Current section highlighted in outline as user scrolls
- Toggle outline with keyboard shortcut (e.g., Cmd+Shift+O)
- Width: ~200px, resizable, collapsible

### Minimap (Secondary/Optional)
- Slim column on the right edge showing a zoomed-out view of the entire file
- Highlight the currently visible region
- Click to jump to a position
- Only show for code files (not markdown preview or tree view)

## Implementation Notes

### Outline
- For markdown: parse headings from the swift-markdown AST (already parsed for preview)
- For JSON/YAML: extract top-level keys from parsed structure
- For code: use regex to find `func `, `class `, `def `, `function ` etc. (later: Tree-sitter symbols)
- Implement as an `NSOutlineView` in a side panel within the preview container
- Sync scroll position with outline selection using `NSTextView.visibleRect` observation

### Minimap
- Render a scaled-down version of the text content into a narrow `NSView`
- Use `NSLayoutManager` to get line positions, draw colored rectangles for syntax regions
- Overlay a semi-transparent rectangle showing the visible viewport

## Files to Create

- `totalcommander/UI/Preview/DocumentOutlineView.swift`
- `totalcommander/UI/Preview/MinimapView.swift` (optional)

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — add outline toggle
- `totalcommander/UI/Preview/CodePreviewViewController.swift` — expose document symbols
- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — expose heading list

## Acceptance Criteria

- [ ] Markdown files show heading hierarchy in outline
- [ ] JSON files show key hierarchy in outline
- [ ] Code files show function/class names in outline
- [ ] Clicking outline item scrolls to that section
- [ ] Current section highlighted as user scrolls
- [ ] Outline toggles with keyboard shortcut
- [ ] Theme-aware styling
