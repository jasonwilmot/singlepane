# Project Brief: Velocity — A Blazing-Fast File Manager for macOS

> This document defines the product vision, technical principles, and engineering guidelines for building a best-in-class native macOS file manager. It is the operating contract between product, design, and engineering.

---

## 1. Vision

Build the fastest, most capable file manager ever made for macOS. A tool so fast that file operations feel instantaneous, search results appear as you type, terminal input echoes immediately, and navigation never drops a frame. The app should feel like a precision instrument — powerful enough for sysadmins and developers, intuitive enough for anyone who outgrows Finder.

**Inspirations:**
- **Total Commander** (Windows) — The gold standard for keyboard-driven, dual-pane file management. 30+ years of power-user trust. We take its keyboard-first philosophy, archive-as-folder transparency, and plugin extensibility.
- **Path Finder** (macOS, Cocoatech) — The most feature-rich Finder replacement on Mac. We take its modular UI architecture, Drop Stack concept, embedded terminal, and deep macOS integration.
- **Commander One** (macOS, Eltima) — A modern dual-pane manager built in Swift. We take its cloud mounting model, archive handling breadth, and clean native aesthetic.
- **EasyFind** (macOS, DEVONtechnologies) — Instant file search without Spotlight indexing. We take its boolean/regex search, zero-index search philosophy, and raw filesystem scanning speed.

We are not building a Finder skin. We are building a professional-grade file operating system.

---

## 2. Core Principles

### Performance is the Feature
- Every interaction must complete in under 16ms (60fps) or provide immediate visual feedback.
- Directory listing of 100,000+ files must render without stutter.
- Search must return first results within 200ms of keystroke.
- File copy/move operations must saturate disk I/O — never be CPU-bound.
- Cold launch to usable UI: under 1 second. Warm launch: under 300ms.

### Keyboard-First, Mouse-Friendly
- Every operation must be achievable without touching the mouse.
- Follow the Norton Commander / Total Commander function key paradigm (F3 view, F4 edit, F5 copy, F6 move, F7 mkdir, F8 delete) as defaults, fully remappable.
- Command palette (Cmd+Shift+P) for discoverability of all actions.
- Mouse and trackpad interactions should feel native macOS — no fighting platform conventions.

### Native or Nothing
- Use AppKit and SwiftUI where each is strongest. No Electron. No web views. No cross-platform abstraction layers.
- Respect macOS conventions: system menu bar, Services menu, standard shortcuts, Handoff, system appearance, accessibility.
- Use system frameworks (Spotlight, FSEvents, Security, Keychain) instead of reinventing them.

### Modular by Design
- The UI is composed of draggable, dockable modules (inspired by Path Finder).
- Users can build their own workspace layouts. Layouts are saveable and switchable.
- Features ship as modules — easy to add, remove, and maintain independently.

### Terminal Is a First-Class Surface
- Terminal emulation must feel as fast as native terminal apps.
- Keystroke-to-echo latency and scroll performance are release-gated metrics.
- File-to-terminal workflows must be frictionless, including drag-and-drop path insertion.

---

## 3. Key Features

### 3.1 Dual-Pane Browser
- Two independent file panels, each with unlimited tabs.
- Panels can be horizontal or vertical split, or collapsed to single-pane.
- Each panel maintains independent navigation history, sort order, view mode, and filter state.
- Tab presets: save and restore named tab configurations (e.g., "Web Project", "System Admin").

### 3.2 Search Engine (Critical Differentiator)
This is where we win. Search must be best-in-class — faster and more capable than Spotlight, EasyFind, or any competitor.

**Dual-mode search architecture:**
- **Indexed search**: Build and maintain our own file metadata index using a persistent SQLite/FTS5 database. Index file names, paths, sizes, dates, extended attributes, tags, and content hashes. Use FSEvents to keep the index current in real-time.
- **Raw filesystem search**: For unindexed volumes or when the user needs guaranteed completeness, perform direct filesystem enumeration using low-level POSIX APIs (`fts_open`, `fts_read`) or `NSFileManager.enumerator` with prefetching. This is the EasyFind model.

**Search capabilities:**
- Filename search with glob patterns and fuzzy matching.
- Full-text content search across file contents.
- Boolean operators (AND, OR, NOT) and parenthetical grouping.
- Regular expression support.
- Search inside archives (ZIP, TAR, etc.) without extraction.
- Search across mounted cloud volumes.
- Duplicate file finder (by hash, name, or size).
- Saved searches / smart folders.
- Search scope: current folder, folder tree, volume, all volumes, specific paths.

**Search UX:**
- Results stream in as they are found — never wait for completion.
- Instant filter-as-you-type in any directory listing.
- Search bar with syntax highlighting for complex queries.
- Recent searches with one-click re-run.

### 3.3 File Operations
- Background operation queue with per-operation progress, pause, resume, cancel, and retry.
- Conflict resolution dialog with file preview comparison (size, date, thumbnail) — inspired by Total Commander.
- Batch rename with live preview: regex, counters, date insertion, metadata fields (EXIF, ID3), find-and-replace, case conversion.
- File splitting and combining.
- Secure delete (overwrite before unlink).
- Symlink and hard link creation from context menu.
- Folder comparison and synchronization (FolderSync) between any two locations.

### 3.4 Archive Handling
Archives are first-class citizens — browsable as folders, searchable, and editable in-place.

**Create/modify:** ZIP, 7z, TAR, TAR.GZ, TAR.BZ2, TAR.XZ.
**Extract/browse:** All of the above plus RAR, ISO, DMG, CAB, XAR, XIP.
**Features:**
- Navigate into archives as if they are directories.
- Copy files between archives without intermediate extraction.
- Edit files inside archives — extract to temp, open, save, re-pack automatically.
- Password-protected archive creation (ZIP AES-256, 7z).
- Adjustable compression levels.

### 3.5 Lightning-Fast Embedded Terminal
Terminal is not an add-on. It is part of the primary workflow.

**Core terminal capabilities:**
- Native terminal emulation powered by **SwiftTerm + PTY**.
- Keystroke-to-echo latency optimized for local shells and SSH sessions.
- Multiple sessions with horizontal tabs or vertical tabs.
- Side-by-side terminal splits for parallel workflows.
- Optional auto-follow current directory from active file pane.

**Drag files into terminal for reference:**
- Drag one or more files/folders from file panes directly into terminal.
- Insert shell-safe escaped paths at cursor position (no broken commands from spaces/special chars).
- Multi-select drag inserts space-delimited escaped paths.
- Modifier for relative-path insertion from terminal CWD.
- Works with internal file panes and external drags from Finder.

### 3.6 Modules System
Draggable, dockable panels that users arrange into custom layouts:

| Module | Description |
|---|---|
| **Preview** | Quick Look-powered inline preview for any file type |
| **Terminal** | SwiftTerm-based terminal with PTY sessions, tabs, and splits |
| **Hex Viewer** | Binary/hex file inspection and editing |
| **Info** | Detailed file metadata, extended attributes, Spotlight metadata |
| **Permissions** | Unix permissions + ACL editor |
| **Git Status** | Repository status, branch, staged/unstaged changes |
| **Processes** | System process viewer with kill capability |
| **Drop Stack** | Temporary staging shelf for multi-step file moves |
| **Tags** | macOS tag management and star ratings |
| **Bookmarks** | Quick-access folder bookmarks bar |
| **Disk Usage** | Visual treemap of disk space consumption |
| **Image Browser** | Thumbnail grid for image-heavy folders |
| **Search** | Persistent search panel with saved queries |

### 3.7 Built-in File Viewer
Invoked with F3 or spacebar (Quick Look parity).
- Text with syntax highlighting (language auto-detection).
- Hex/binary view.
- Image viewer with zoom, rotate, EXIF overlay.
- Media playback (audio/video via AVFoundation).
- Markdown rendered preview.
- HTML rendering.
- PDF viewer.
- View files inside archives and on remote servers without downloading the entire file.

### 3.8 iOS / External Device Mounting
- Mount iPhone/iPad via USB for file browsing (where iOS allows).
- MTP device support (cameras, Android devices).
- External drive management with eject, format, partition info.

---

## 4. Technical Architecture & Stack

### Language & Frameworks
| Layer | Technology | Rationale |
|---|---|---|
| **Primary language** | Swift 6+ (strict concurrency) | Performance, safety, modern async/await |
| **UI framework** | AppKit (primary) + SwiftUI (leaf views, settings) | AppKit for full control over performance-critical views; SwiftUI for rapid iteration on secondary UI |
| **Terminal emulation** | SwiftTerm + PTY (`openpty`, `forkpty`) | Low-latency native terminal rendering and process control |
| **File system monitoring** | FSEvents API | Real-time, low-overhead directory change notifications from the kernel |
| **File enumeration** | POSIX `fts(3)` / `getattrlistbulk` | Fastest possible directory traversal — bypasses Foundation overhead |
| **Search index** | SQLite with FTS5 | Full-text search with ranking, proven at scale, single-file database |
| **Networking** | NWConnection (Network.framework) | Modern Apple networking with TLS, proxy, and multiplexing support |
| **Cloud APIs** | URLSession + provider SDKs | Native HTTP/2, background transfers |
| **Archive handling** | libarchive + minizip-ng | C libraries with Swift wrappers — fast, broad format support |
| **Concurrency** | Swift Structured Concurrency (async/await, TaskGroup, actors) | Safe, performant parallelism without GCD callback hell |
| **Image/Media** | AVFoundation, CoreImage, Vision | System frameworks for preview, thumbnails, and image analysis |
| **Data persistence** | SwiftData / SQLite (direct) | User preferences, bookmarks, connection configs, search index |
| **IPC / Extensions** | XPC Services | Sandboxed helper processes for privileged operations |
| **Distribution** | App Store + direct DMG (notarized) | Reach + freedom from App Store sandbox limitations |

### Performance-Critical Design Decisions

**1. Virtual Scrolling for File Lists**
Never render more rows than are visible. Use `NSTableView` with a virtualized data source. For directories with 500K+ items, paginate the data source and fetch rows on demand. Pre-sort and pre-filter in a background actor before handing to the UI.

**2. Off-Main-Thread Everything**
- File enumeration: background actor.
- Search indexing: background XPC service.
- Archive operations: background actor with progress reporting via `AsyncStream`.
- Terminal PTY reads/writes: background stream processing with throttled UI flushes.
- Thumbnail generation: background `TaskGroup` with concurrency limit.
- Network transfers: `URLSession` background tasks.
- The main thread does **nothing** except render UI and handle input events.

**3. File Metadata Caching**
Maintain an in-memory LRU cache of file metadata (stat results, thumbnails, extended attributes) keyed by inode + modification time. Invalidate via FSEvents. This eliminates redundant `stat()` calls when switching between tabs or re-sorting.

**4. Incremental Search Index**
The search index is updated incrementally via FSEvents, not rebuilt. On first launch for a new volume, build the initial index in a background XPC service with throttled I/O priority (`IOPOL_THROTTLE`) to avoid impacting system performance. Target: full index of a 1M file volume in under 60 seconds.

**5. Zero-Copy File Operations**
Use `clonefile(2)` on APFS volumes for instant copy-on-write duplicates. Use `fcopyfile(3)` for cross-volume copies. Use `renameat(2)` for same-volume moves. Never read file data into userspace for move/copy operations when the kernel can do it.

**6. Lazy Thumbnail Generation**
Generate thumbnails only for visible rows. Use QuickLook Thumbnailing framework (`QLThumbnailGenerator`) with a two-tier cache: in-memory (NSCache, 500 items) and on-disk (file-backed cache in `~/Library/Caches/`). Show file-type icon placeholder until thumbnail is ready.

**7. Memory-Mapped File Viewing**
The built-in viewer uses `mmap(2)` for large files. Never load an entire file into memory. For text files, detect encoding and render only the visible window. For hex view, render the visible byte range only.

**8. Lightning Terminal Pipeline**
- PTY data consumed via non-blocking reads with back-pressure aware buffering.
- Frame-coalesced terminal paints to avoid jank during high output.
- Ring-buffer scrollback to cap memory usage under sustained output.
- Escape-sequence parser and renderer profiled under `vim`, `htop`, `git log`, and large colored output streams.

### Architecture Layers

```
┌─────────────────────────────────────────────┐
│                  UI Layer                    │
│  AppKit Views / SwiftUI / Module System      │
├─────────────────────────────────────────────┤
│              ViewModel Layer                 │
│  @Observable models, async data streams      │
├─────────────────────────────────────────────┤
│              Service Layer                   │
│  FileService, SearchService, ArchiveService  │
│  CloudService, TransferService, IndexService │
│  TerminalService (PTY sessions + routing)    │
├─────────────────────────────────────────────┤
│             Foundation Layer                 │
│  POSIX wrappers, SQLite, libarchive,         │
│  FSEvents, XPC, Network.framework, PTY       │
└─────────────────────────────────────────────┘
```

- **UI Layer**: Thin. Views bind to ViewModels. No business logic in views.
- **ViewModel Layer**: `@Observable` classes that expose data as published properties and `AsyncSequence` streams. Handles user intent -> service calls.
- **Service Layer**: Stateless actors that perform work. Each service owns its domain (files, search, archives, cloud, terminal). Services communicate via Swift protocols — easily testable, mockable.
- **Foundation Layer**: Thin Swift wrappers around C APIs and system frameworks. No Foundation types in the hot path — use raw file descriptors, C strings, and `UnsafeBufferPointer` where performance demands it.

### Sandbox & Security
- Ship with App Sandbox enabled for App Store.
- Direct distribution build uses temporary entitlement exceptions only where necessary (full disk access, privileged file operations).
- Use XPC Services for privileged helpers (format disk, modify system files).
- All remote credentials stored in Keychain, never in plaintext.
- Use Security.framework for code signing validation of plugins/extensions.

---

## 5. UX Principles

### Speed is UX
- If the user perceives a delay, we have failed. Optimistic UI updates — show the expected result immediately, reconcile with reality in the background.
- Progress indicators for operations > 500ms. No spinners for operations < 500ms.
- Animations serve function (showing spatial relationships), never decoration. Keep them under 200ms.
- Terminal typing and output must feel immediate under both idle and high-output shells.

### Progressive Disclosure
- Default view is clean and simple — single pane, essential toolbar, no modules.
- Power features reveal themselves: dual pane via a split gesture or shortcut, modules via a menu, advanced search via typing operators.
- First-run experience should feel simpler than Finder. Week-two experience should feel like a superpower.

### Information Density is a Spectrum
- Support column view, list view, icon view, gallery view, and a compact "brief mode" (filename-only columns, Total Commander style).
- Users choose their density. Power users want maximum information per pixel. Casual users want breathing room.

### Consistency with macOS
- Follow Apple Human Interface Guidelines for standard controls, menus, and keyboard shortcuts.
- Support system Dark Mode, accent colors, accessibility settings (VoiceOver, reduced motion, increased contrast).
- Drag and drop integrates with Finder, Desktop, and other apps via standard pasteboard types.
- Respect system settings for file date formats, units (MB vs MiB), and language.

### Drag Files to Terminal UX
- Dragging files/folders into terminal inserts escaped paths, not opaque attachments.
- The insertion preview is visible before drop commit.
- Multi-file drops preserve deterministic ordering.
- Relative-path insertion is available as a modifier action.
- Behavior is identical whether dragging from internal panes or Finder.

### Shortcuts & Command Palette
- Global shortcut to summon the app (configurable, default: Ctrl+Space).
- Command palette (Cmd+Shift+P) surfaces every action with fuzzy search.
- Vim-style navigation optional (hjkl + modal commands) as an opt-in setting.
- All shortcuts displayed inline in menus and discoverable via the command palette.

---

## 6. Quality Gates

These are non-negotiable requirements before any release:

| Metric | Target |
|---|---|
| Cold launch to interactive | < 1 second |
| Directory listing (10K files) | < 100ms to first paint |
| Directory listing (100K files) | < 500ms to first paint, no frame drops during scroll |
| Search first result (indexed) | < 50ms |
| Search first result (raw filesystem, local SSD) | < 200ms |
| Terminal keystroke-to-echo (local shell, p95) | < 8ms |
| Terminal startup to first prompt (local shell) | < 150ms |
| File path drag-drop into terminal to inserted text | < 50ms |
| Path escaping correctness for dragged files | 100% in test matrix |
| File copy throughput (local SSD) | > 90% of theoretical disk bandwidth |
| Memory usage (idle, single tab) | < 80MB |
| Memory usage (10 tabs, 2 cloud mounts) | < 250MB |
| Accessibility audit | Zero critical VoiceOver issues |
| Crash rate | < 0.1% of sessions |

### Testing Strategy
- Unit tests for all Service layer logic (file operations, search, archive handling, terminal session management).
- Integration tests against real filesystems (APFS, ExFAT, network volumes, disk images).
- UI tests for critical flows (navigation, search, copy/move, drag and drop, file-to-terminal drops).
- Performance tests that run in CI and fail the build if regressions exceed 10%.
- Terminal conformance tests (ANSI/VT sequences, color, cursor movement, scroll regions).
- Path insertion tests for spaces, quotes, unicode, shell metacharacters, and multi-file drag order.
- Fuzz testing for archive parsing (libarchive edge cases, malformed archives).
- Memory leak detection via Instruments / Xcode Memory Graph in CI.

---

## 7. Milestone Priorities

**Phase 1 — Foundation (MVP)**
Single and dual-pane browser. Directory listing with virtual scroll. Basic file operations (copy, move, rename, delete, create folder). Column/list/icon views. Keyboard navigation with function keys. In-directory filter-as-you-type. Basic file viewer (text, image, hex). FSEvents-based live directory updates. Embedded terminal dock using SwiftTerm + PTY with horizontal/vertical tabs, split terminals, and drag files into terminal path insertion.

**Phase 2 — Search & Speed**
Background search index service (XPC). Indexed filename search with fuzzy matching. Full-text content search. Boolean and regex search operators. Duplicate file finder. Search inside archives. Terminal performance hardening under high-output workloads.

**Phase 3 — Power Features**
Module system with draggable panels. Drop Stack. Advanced terminal profiles and workspace presets. Batch rename with preview. Archive browsing and creation. Folder comparison and sync. Git status module.

**Phase 4 — Reliability and Team Workflows**
Operation history and undo hardening. Workspace portability. Shared team layout presets. Telemetry-driven performance tuning on large repositories and mixed storage environments.

**Phase 5 — Polish & Ecosystem**
Custom themes. Plugin/extension API. iOS device mounting. Disk usage visualization. Performance optimization pass. App Store submission.

---

## 8. What We Will Not Do

- We will not build a web-based or Electron app.
- We will not support operating systems other than macOS.
- We will not bundle a sync engine — we mount and browse, we do not replicate.
- We will not implement our own filesystem or virtual filesystem layer — we use the OS.
- We will not sacrifice performance for feature count. Every feature must meet the performance bar or it doesn't ship.
- We will not ignore accessibility. VoiceOver and keyboard navigation are first-class from day one.

---

*This is a living document. Update it as architectural decisions are made and validated.*

