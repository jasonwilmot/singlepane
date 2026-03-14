# Large File Safety — Implementation Plan

**Overall Progress:** `100%`

## TLDR
Prevent crashes when opening large files by adding size checks, using mmap for read-only preview of large files, showing an inline warning banner in the editor for large files, and implementing mmap-based search so the find bar works across the full file.

## Critical Decisions
- **Warning, not blocking:** Editor shows a dismissible inline banner for large files — never refuses to open
- **mmap for read-only, full load for editor:** Code preview uses mmap + visible-window rendering for files >1MB; editor loads normally with a performance warning
- **mmap-based search:** Find bar searches the mapped file bytes directly so search works on non-visible text in large files
- **Skip pretty-printing for large files:** JSON/plist files above the threshold load as-is — no re-serialization
- **File size only in warning banner:** No permanent file size display — users don't care unless there's a reason to

## Tasks:

- [x] 🟩 **Step 1: Create LargeFileReader service**
  - [x] 🟩 New `totalcommander/Services/LargeFileReader.swift` — actor wrapping `Data(contentsOf:options:.mappedIfSafe)`
  - [x] 🟩 Line-offset index: background scan of `\n` positions in mapped data, returns `[Int]` of byte offsets
  - [x] 🟩 `readLines(range:)` method — extracts a window of lines from mapped data as `String`
  - [x] 🟩 `searchAll(query:)` method — case-insensitive byte scan of mapped data, returns match positions
  - [x] 🟩 File size threshold constants + URL extension + formatter helper
  - [x] 🟩 Add to Xcode project (pbxproj)

- [x] 🟩 **Step 2: Size-gated loading in CodePreviewViewController**
  - [x] 🟩 Check file size before `String(contentsOf:)` in `loadFile(at:)`
  - [x] 🟩 Files <1MB: load normally (current behavior)
  - [x] 🟩 Files ≥1MB: use LargeFileReader mmap, render only the visible window of lines into the NSTextView
  - [x] 🟩 Hook scroll events to update the visible window as user scrolls (debounced)
  - [x] 🟩 Update LineNumberGutterView to accept `overrideTotalLineCount` and `lineNumberOffset`
  - [x] 🟩 Skip pretty-printing for files ≥1MB

- [x] 🟩 **Step 3: Size-gated loading in EditorViewController**
  - [x] 🟩 Check file size before `String(contentsOf:)` in `loadFile(at:)`
  - [x] 🟩 Files ≥1MB: show a dismissible inline warning banner with file size
  - [x] 🟩 Still load the full file into NSTextView for editing
  - [x] 🟩 Skip pretty-printing for files ≥1MB

- [x] 🟩 **Step 4: Size-gated loading in MarkdownPreviewViewController**
  - [x] 🟩 Check file size before `String(contentsOf:)` in `loadMarkdownFile(at:)` and `loadHTMLFile(at:)`
  - [x] 🟩 Very large markdown (≥10MB): truncate to first 10,000 lines with inline warning
  - [x] 🟩 Very large HTML (≥10MB): show warning message suggesting code preview

- [x] 🟩 **Step 5: Syntax highlighting limits for large files**
  - [x] 🟩 CodePreviewViewController mmap mode: highlight only the visible window of text (re-highlight on scroll)
  - [x] 🟩 EditorViewController large file mode: incremental highlighting via `CodeSyntaxHighlighter.incrementalMode`
  - [x] 🟩 Added `highlightRange(_:)` to `SyntaxHighlighting` protocol with default implementation

- [x] 🟩 **Step 6: mmap-based search for find bar**
  - [x] 🟩 In `PreviewContainerViewController`, detect when code preview is in mmap mode
  - [x] 🟩 Route find bar searches to `LargeFileReader.searchAll(query:)` instead of NSTextView string search
  - [x] 🟩 Map match byte offsets to line numbers via the line-offset index
  - [x] 🟩 Scroll to matched line (update visible window) and highlight the match
  - [x] 🟩 Next/previous navigation works across the full file

- [x] 🟩 **Step 7: Cancellation of in-flight file loads**
  - [x] 🟩 Track `fileLoadTask` in PreviewContainerViewController, `loadTask` in CodePreviewViewController
  - [x] 🟩 Cancel previous async work when a new file is selected
  - [x] 🟩 Guard against stale results with `Task.isCancelled` checks

- [x] 🟩 **Step 8: Loading spinner for slow loads**
  - [x] 🟩 Show a lightweight NSProgressIndicator spinner on the content area when file load exceeds 200ms
  - [x] 🟩 Dismiss on load completion or cancellation
