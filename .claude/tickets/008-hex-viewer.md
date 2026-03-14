# 008: Hex Viewer Module

**Priority:** P2
**Effort:** Medium
**Labels:** Feature, Preview
**Phase:** 2 — Differentiator

## Problem

CLAUDE.md lists Hex Viewer as a core module. Binary files currently show a placeholder in preview. Developers and sysadmins frequently need to inspect binary files, executables, data files, and corrupted files at the byte level.

## Requirements

### Display
- Three-column layout: offset | hex bytes | ASCII representation
- 16 bytes per row (standard hex viewer layout)
- Offset column: 8-digit hex address (e.g., `00000000`, `00000010`)
- Hex column: bytes displayed as two-digit hex with space separators, grouped in pairs of 8
- ASCII column: printable characters shown as-is, non-printable shown as `.`
- Monospace font throughout (from FontManager)

### Interaction
- Click a byte to select it — highlight in both hex and ASCII columns
- Click-drag to select a range
- Selection shows byte value in status bar (decimal, hex, octal, binary, and character)
- Cmd+G: go to offset
- Cmd+F: find hex pattern or ASCII string

### Performance
- mmap-backed: never load entire file into memory
- Render only visible rows (virtual scrolling)
- Must handle files up to 4GB without issues
- Smooth 60fps scrolling

### Theme
- Offset column: muted color
- Hex bytes: primary text color, alternating background on byte groups for readability
- ASCII column: slightly different background
- Non-printable characters: dimmed color
- Selected bytes: theme accent color

## Implementation Notes

- Use NSTableView or custom NSView with virtual row rendering
- mmap the file via `Data(contentsOf:options:.mappedIfSafe)` or raw `mmap(2)`
- Calculate visible byte range from scroll position: `firstVisibleRow * 16` to `(lastVisibleRow + 1) * 16`
- Render only that range
- Route binary/unknown file types to this viewer from `PreviewContainerViewController`

## Files to Create

- `totalcommander/UI/Preview/HexViewerViewController.swift`
- `totalcommander/UI/Preview/HexViewerDataSource.swift`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — route binary files to hex viewer

## Acceptance Criteria

- [ ] Binary files open in hex viewer by default
- [ ] Three-column layout renders correctly
- [ ] Click selects byte, shows value in all representations
- [ ] Go-to-offset works
- [ ] Find hex/ASCII works
- [ ] 1GB file opens instantly, scrolls at 60fps
- [ ] Memory usage stays flat regardless of file size
- [ ] Theme-aware colors
