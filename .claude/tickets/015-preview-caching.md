# 015: Preview Caching (LRU Cache for Rendered Content)

**Priority:** P3
**Effort:** Small
**Labels:** Improvement, Preview
**Phase:** 2 — Differentiator

## Problem

Switching between files or tabs re-renders everything from scratch. Selecting a file, switching to another, then switching back re-loads and re-highlights the first file. This creates perceptible lag, especially for large files or markdown with complex rendering. CLAUDE.md § 4.3 specifies an in-memory LRU cache for file metadata — the same pattern should apply to preview content.

## Requirements

### Cache Scope
- Cache rendered preview content keyed by file path + modification time
- Types of cached content:
  - **Code preview**: `NSAttributedString` (syntax-highlighted)
  - **Markdown preview**: generated HTML string
  - **JSON/YAML tree**: parsed tree model
  - **Image preview**: decoded `NSImage` (for non-trivial sizes)

### Cache Policy
- LRU eviction with configurable max entries (default: 20 files)
- Max memory budget: 50MB (evict largest entries first when exceeded)
- Invalidate on file modification (check `stat.st_mtime` before using cached version)
- Invalidate on theme change (colors embedded in cached content)
- Invalidate on font change (font embedded in attributed strings)

### Cache Hit Behavior
- On cache hit: display immediately (< 1ms), no file I/O
- On cache miss: load normally, store result after rendering

### Cache Miss Optimization
- Pre-cache adjacent files in the file list (speculative prefetch for likely next selections)
- Prefetch on background thread, low priority

## Implementation Notes

- Use `NSCache` for automatic memory management and thread safety
- Cache key: `"\(filePath):\(modificationDate.timeIntervalSince1970):\(themeId):\(fontName)"`
- Wrap cached content in a `PreviewCacheEntry` struct with metadata (size, creation time)
- For theme/font invalidation: clear entire cache on theme or font change (simpler than per-entry invalidation)
- Speculative prefetch: when a file is selected, also queue the file above and below it in the list

## Files to Create

- `totalcommander/Services/PreviewCache.swift`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — check cache before loading
- `totalcommander/UI/Preview/CodePreviewViewController.swift` — store/retrieve cached attributed strings
- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — store/retrieve cached HTML

## Acceptance Criteria

- [ ] Switching back to a previously viewed file displays instantly (no re-render)
- [ ] Modifying a file and switching back shows updated content (cache invalidated)
- [ ] Changing theme clears cache and re-renders
- [ ] Memory usage stays under 50MB for cache
- [ ] Cache holds at least 20 recently viewed files
- [ ] No stale content ever displayed (modification time check)
