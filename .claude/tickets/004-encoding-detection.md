# 004: File Encoding Auto-Detection

**Priority:** P1
**Effort:** Medium
**Labels:** Bug, Improvement
**Phase:** 1 — Must-Have

## Problem

Both `CodePreviewViewController` and `EditorViewController` hardcode UTF-8 encoding. If a file uses Latin-1, Shift-JIS, Windows-1252, or any other encoding, the preview will show garbled text. Worse, the editor will **silently corrupt the file** by saving it as UTF-8, destroying the original encoding.

## Requirements

- Auto-detect file encoding when loading for preview or editing
- Support at minimum: UTF-8, UTF-16 (LE/BE), UTF-32, ASCII, Latin-1 (ISO-8859-1), Windows-1252, Shift-JIS, EUC-JP, GB2312/GBK
- Display detected encoding in the preview toolbar/status bar
- Allow manual encoding override (dropdown or command palette)
- Editor must save in the same encoding it loaded (never silently convert)
- If encoding cannot be determined, fall back to UTF-8 and display a warning

## Implementation Notes

- Use `String.Encoding` detection via `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`
- Or use ICU's `ucsdet_detect` for more robust detection
- Check for BOM (Byte Order Mark) first — definitive for UTF-16/UTF-32
- Store the detected encoding alongside the file URL in the view controller
- Pass encoding through to save operations

## Files to Modify

- `totalcommander/UI/Preview/CodePreviewViewController.swift` — use detected encoding
- `totalcommander/UI/Preview/EditorViewController.swift` — load and save with detected encoding
- New: `totalcommander/Services/EncodingDetector.swift`

## Acceptance Criteria

- [ ] Latin-1 encoded files display correctly in preview and editor
- [ ] Saving a Latin-1 file from the editor preserves Latin-1 encoding
- [ ] UTF-16 files with BOM are detected and displayed correctly
- [ ] Detected encoding shown in UI
- [ ] User can override encoding manually
- [ ] No data corruption on round-trip (open → save) for any supported encoding
