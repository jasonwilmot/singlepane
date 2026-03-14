# 003: Large File Safety (Size Guard + mmap)

**Priority:** P1
**Effort:** Medium
**Labels:** Improvement, Preview
**Phase:** 1 — Must-Have

## Problem

Both `CodePreviewViewController` and `EditorViewController` load entire files into memory as `String(contentsOf:encoding:)`. There are no size checks. Opening a 500MB log file or binary will cause memory pressure or crash. CLAUDE.md § 4.7 specifies memory-mapped file viewing for large files.

## Requirements

### Code Preview (Read-Only)
- Files < 1MB: load normally (current behavior)
- Files 1MB–100MB: use `mmap(2)` to map the file, render only the visible window of lines
- Files > 100MB: show a warning with file size, offer to open first 10,000 lines or open in external editor
- Display file size in the preview toolbar/status area

### Editor (Read-Write)
- Files < 1MB: load normally
- Files 1MB–10MB: load with warning ("Large file — editing may be slow")
- Files > 10MB: refuse to open in editor, suggest code preview instead
- Never allow saving a file that was loaded via mmap (read-only constraint)

### General
- Show a lightweight spinner/progress indicator for files that take >200ms to load
- Cancel previous file load when a new file is selected (rapid clicking through file list)

## Implementation Notes

- Use `mmap(2)` or `DispatchData`/`Data(contentsOf:options: .mappedIfSafe)` for mapped reads
- For the visible-window approach: calculate which byte range corresponds to the visible lines, extract and render only that range
- Need a line-offset index for large files (scan for `\n` positions in a background pass)
- Per CLAUDE.md: "The built-in viewer uses mmap(2) for large files. Never load an entire file into memory."

## Files to Modify

- `totalcommander/UI/Preview/CodePreviewViewController.swift`
- `totalcommander/UI/Preview/EditorViewController.swift`
- New: `totalcommander/Services/LargeFileReader.swift` (mmap wrapper + line index)

## Acceptance Criteria

- [ ] Opening a 50MB text file in code preview does not spike memory usage
- [ ] Opening a 500MB file shows a warning, does not crash
- [ ] Visible content renders within 500ms for any file size
- [ ] Editor refuses files > 10MB with a clear message
- [ ] Rapid file selection changes cancel previous loads
- [ ] File size displayed somewhere in the preview UI
