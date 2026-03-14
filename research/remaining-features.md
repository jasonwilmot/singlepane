# Remaining Features — Gap Analysis

> What still needs to be built based on all research, tickets, and the project brief vs. current implementation state.
> Generated 2026-03-11.

---

## File Manager

| Feature | Source | Notes |
|---|---|---|
| **Full search engine** (indexed + raw filesystem) | Ticket #53, CLAUDE.md Phase 2 | Biggest missing piece — "this is where we win" per the brief. SQLite/FTS5 index, FSEvents updates, raw POSIX enumeration fallback, boolean/regex operators, duplicate finder, search inside archives |
| **Command palette** (Cmd+Shift+P) | CLAUDE.md core | Primary discoverability mechanism — fuzzy search over all actions |
| **F-key keyboard shortcuts** (F3/F4/F5/F6/F7/F8) | CLAUDE.md core | Norton Commander paradigm — view, edit, copy, move, mkdir, delete. Fully remappable |
| **Background operation queue** | CLAUDE.md §3.3 | Per-operation progress, pause, resume, cancel, retry. Conflict resolution dialog with file preview comparison |
| **Batch rename with live preview** | CLAUDE.md Phase 3 | Regex, counters, date insertion, metadata fields, find-and-replace, case conversion |
| **Archive browsing** (ZIP/TAR as folders) | CLAUDE.md §3.4 | Browse, extract, create, edit in-place. libarchive + minizip-ng |
| **Column view / icon view / gallery view** | CLAUDE.md §5 | Only list view exists. Need column, icon, gallery, and compact "brief mode" |
| **Virtual scrolling for 100K+ files** | CLAUDE.md perf targets | Current NSTableView won't handle 100K files at 60fps. Need virtualized data source with on-demand row fetching |
| **App state restoration** | Ticket #54 | Persist and restore window layout, tabs, directories, selections across launches |
| **Folder comparison & sync** | CLAUDE.md Phase 3 | Side-by-side diff between any two locations |
| **Drop Stack** | CLAUDE.md Phase 3 | Temporary staging shelf for multi-step file moves |
| **Modules system** (draggable dockable panels) | CLAUDE.md Phase 3 | Info, Permissions, Git Status, Processes, Disk Usage, Tags, Bookmarks, Image Browser, Search |
| **Duplicate file finder** | CLAUDE.md Phase 2 | By hash, name, or size |
| **Symlink / hard link creation** | CLAUDE.md §3.3 | From context menu |
| **Secure delete** | CLAUDE.md §3.3 | Overwrite before unlink |
| **File splitting and combining** | CLAUDE.md §3.3 | Split large files, recombine |
| **Vim-style navigation** (opt-in) | CLAUDE.md §5 | hjkl + modal commands as a setting |
| **Swappable panel content** | Ticket #33 | Swap what's displayed in each panel slot |
| **iOS / external device mounting** | CLAUDE.md §3.8, Phase 5 | iPhone/iPad via USB, MTP devices, external drive management |
| **Cloud volume mounting** | CLAUDE.md Phase 5 | Dropbox, Google Drive, S3 — mount and browse |
| **XPC helper services** | CLAUDE.md §4 | Privileged operations (format disk, modify system files), sandboxed search indexing |

---

## Terminal

| Feature | Source | Notes |
|---|---|---|
| **Broadcast input** (type in all splits) | Kitty/WezTerm research P1 | Send keystrokes to all visible terminal sessions simultaneously |
| **Inline image rendering** (Sixel / iTerm2 protocol) | Kitty/WezTerm research P1 | Render images inline in terminal output |
| **Terminal profiles** (per-tab shell/env/theme) | CLAUDE.md Phase 3 | Named profiles with different shell, environment, theme, font per tab |
| **SSH domain awareness** | WezTerm research | Detect SSH sessions, adjust behavior (e.g., disable local CWD sync) |

> **Note:** The terminal is the most complete area. Hints mode, find bar, link detection, OSC 133, splits, and drag-drop path insertion are all implemented or partially implemented. The items above are the remaining gaps from research.

---

## Reader / Preview

| Feature | Source | Notes |
|---|---|---|
| **Hex viewer** | Ticket #008, editor research | Binary/hex file inspection and editing |
| **JSON/YAML collapsible tree view** | Ticket #005 | Expandable/collapsible structured data viewer |
| **Image viewer enhancements** (zoom, rotate, EXIF) | Ticket #009 | Current image preview is basic — needs zoom, rotate, EXIF overlay |
| **PDF viewer** | CLAUDE.md §3.7 | Inline PDF rendering |
| **Find & Replace completion** | Tickets #31, #32 | Find bar exists — replace functionality and regex/case/whole-word toggles may be incomplete |
| **Code folding** | Editor research Tier 2 | Collapse code blocks, functions, imports |
| **Multiple cursors** | Editor research Tier 2 | Multi-cursor editing for batch text changes |
| **Indentation guides** | Editor research Tier 2 | Visual vertical lines showing indent levels |
| **Whitespace visualization** | Editor research Tier 2 | Show spaces/tabs/line-endings as visible glyphs |
| **Tree-sitter migration** | Ticket #011 | Replace regex-based syntax highlighting with Tree-sitter for accuracy and performance |
| **Inline markdown editing** (full Typora-style) | Ticket #010 | Current iA Writer style exists — full inline WYSIWYG not yet implemented |
| **Split preview** (side-by-side) | Ticket #014 | Source + rendered preview side by side |
| **Preview caching** (LRU) | Ticket #015 | Cache rendered previews to avoid re-processing on tab switch |
| **Document outline / minimap** (code files) | Ticket #013 | Markdown outline exists — no minimap or code symbol outline |
| **Syntax highlighting for framework files** | Ticket #55 | SwiftUI, React, Vue, etc. — framework-specific highlighting |

---

## Priority Tiers

### Ship-blocking (Phase 1 MVP gaps)
1. F-key keyboard shortcuts — core identity
2. Command palette — primary discoverability
3. Find & Replace completion — basic editor expectation
4. App state restoration — users expect windows to persist

### High-impact differentiators (Phase 2)
1. Search engine — the single biggest competitive advantage
2. Hex viewer — unique for a file manager
3. JSON/YAML tree view — daily-use for developers
4. Virtual scrolling — needed before claiming performance leadership
5. PDF viewer — expected in any file previewer

### Power features (Phase 3)
1. Batch rename with preview
2. Archive browsing
3. Folder comparison & sync
4. Drop Stack
5. Modules system
6. Terminal profiles
7. Code folding + multiple cursors

### Polish & ecosystem (Phase 4-5)
1. Inline image rendering in terminal
2. iOS device mounting
3. Cloud volume mounting
4. Tree-sitter migration
5. Vim-style navigation
