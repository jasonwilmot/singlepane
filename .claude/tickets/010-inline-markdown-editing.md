# 010: Inline Markdown Editing (Typora / Obsidian Live Preview Model)

**Priority:** P2
**Effort:** Large
**Labels:** Feature, Preview
**Phase:** 2 — Differentiator

## Problem

Current markdown workflow requires switching between Preview tab (rendered WKWebView) and Editor tab (raw NSTextView). This is the weakest flow in our preview pane. Typora pioneered inline WYSIWYG (syntax disappears as you type), and Obsidian's Live Preview mode is now the expected standard. Users shouldn't need to context-switch to edit a README.

## Requirements

### Live Preview Mode
- Single editing surface where markdown is rendered inline as you type
- Cursor position reveals underlying markdown syntax (e.g., clicking on bold text shows `**bold**`)
- Moving cursor away from formatted text re-renders it
- Headings render at correct font sizes inline
- Bold/italic render with actual font weight/style
- Links show as clickable rendered text, reveal `[text](url)` on cursor entry
- Code spans render with monospace background
- Images render inline (or as thumbnails with loading)
- Lists render with proper indentation and bullet/number styling

### Mode Switching
- Three modes accessible from tab bar or keyboard shortcut:
  - **Live Preview** (default): inline WYSIWYG described above
  - **Source**: raw markdown with syntax highlighting (current editor behavior)
  - **Reading**: fully rendered, non-editable (current preview behavior)
- Keyboard shortcut to cycle modes (e.g., Cmd+E)

### Editing Features
- Standard text editing: select, cut, copy, paste, undo/redo
- Paste rich text (from web/Word) converts to markdown automatically
- Paste image saves to a relative path and inserts `![](path)`
- Tab key indents list items
- Enter in a list continues the list
- Cmd+B toggles bold, Cmd+I toggles italic on selection

## Implementation Notes

- This is the most complex ticket. Consider a phased approach:
  1. Phase A: Headings, bold, italic, code spans render inline
  2. Phase B: Links, images, lists
  3. Phase C: Tables, code blocks, blockquotes
- Build on `EditorViewController`'s NSTextView but override `NSTextStorage` to apply live formatting
- Key technique: use `NSTextStorage` delegate to detect markdown patterns around the cursor and toggle between "raw" and "rendered" display per-block
- Obsidian's approach: each block (paragraph, heading, code block) is independently rendered or shown as source based on cursor focus
- Consider using `NSTextContentManager` (TextKit 2) for more granular control if targeting macOS 14+

## Files to Create

- `totalcommander/UI/Preview/LiveMarkdownViewController.swift`
- `totalcommander/UI/Preview/LiveMarkdownTextStorage.swift`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — add Live Preview as a mode option

## Acceptance Criteria

- [ ] Typing `**hello**` immediately renders as **hello** when cursor moves away
- [ ] Clicking into rendered bold text reveals the `**` delimiters
- [ ] Headings render at scaled font sizes inline
- [ ] Code spans render with monospace + background
- [ ] Links are clickable in rendered state, editable when cursor enters
- [ ] Mode switching between Live Preview / Source / Reading works
- [ ] Cmd+B/I toggle formatting on selection
- [ ] Paste rich text converts to markdown
- [ ] Undo/redo works correctly across formatting toggles
- [ ] Performance: no perceptible lag on a 10,000-line markdown document
