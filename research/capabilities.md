# Velocity — Capabilities Overview

Velocity is a native macOS file manager built for speed and power. Below is a summary of its core capabilities organized by domain.

---

## File Browsing

- **Dual-pane browser** with independent panels, unlimited tabs, and horizontal/vertical split
- **Virtual scrolling** for directories with 100K+ files without frame drops
- **Multiple view modes**: column, list, icon, gallery, and compact "brief mode"
- **Live directory updates** via FSEvents — changes appear in real time
- **Tab presets**: save and restore named tab configurations per project or workflow
- **Independent panel state**: each panel maintains its own navigation history, sort order, view mode, and filters

## Search

- **Indexed search** using a persistent SQLite/FTS5 database with real-time FSEvents updates
- **Raw filesystem search** using low-level POSIX APIs for guaranteed completeness on unindexed volumes
- **Filename search** with glob patterns and fuzzy matching
- **Full-text content search** across file contents
- **Boolean operators** (AND, OR, NOT) with parenthetical grouping
- **Regular expression** support
- **Search inside archives** without extraction
- **Duplicate file finder** by hash, name, or size
- **Saved searches / smart folders**
- **Streaming results** — results appear as they are found, never waiting for completion
- **Filter-as-you-type** in any directory listing

## File Operations

- **Background operation queue** with per-operation progress, pause, resume, cancel, and retry
- **Conflict resolution** with file preview comparison (size, date, thumbnail)
- **Batch rename** with live preview: regex, counters, date insertion, metadata fields, find-and-replace, case conversion
- **File splitting and combining**
- **Secure delete** (overwrite before unlink)
- **Symlink and hard link creation** from context menu
- **Folder comparison and synchronization** between any two locations
- **Zero-copy operations** using `clonefile(2)` on APFS, `fcopyfile(3)` cross-volume, `renameat(2)` for same-volume moves

## Archive Handling

- **Create/modify**: ZIP, 7z, TAR, TAR.GZ, TAR.BZ2, TAR.XZ
- **Extract/browse**: all of the above plus RAR, ISO, DMG, CAB, XAR, XIP
- **Browse archives as folders** — navigate into them like directories
- **Copy between archives** without intermediate extraction
- **Edit files inside archives** — extract, edit, and re-pack automatically
- **Password-protected archive creation** (ZIP AES-256, 7z)
- **Adjustable compression levels**

## Embedded Terminal

- **Native terminal emulation** powered by SwiftTerm + PTY
- **Sub-8ms keystroke-to-echo latency** (p95 target)
- **Multiple sessions** with horizontal or vertical tabs
- **Side-by-side terminal splits** for parallel workflows
- **Auto-follow current directory** from active file pane
- **Drag-and-drop path insertion**: drag files from panes into terminal to insert shell-safe escaped paths
- **Multi-file drag** inserts space-delimited escaped paths
- **Modifier key for relative-path insertion** from terminal CWD

## Built-in File Viewer

- **Text** with syntax highlighting and language auto-detection
- **Hex/binary** view
- **Image viewer** with zoom, rotate, and EXIF overlay
- **Media playback** (audio/video via AVFoundation)
- **Markdown** rendered preview
- **HTML** rendering
- **PDF** viewer
- **Remote and archive file viewing** without full download

## Module System

Draggable, dockable panels that users arrange into custom layouts:

| Module | Description |
|---|---|
| Preview | Quick Look-powered inline preview |
| Terminal | SwiftTerm sessions with tabs and splits |
| Hex Viewer | Binary/hex inspection and editing |
| Info | Detailed file metadata and extended attributes |
| Permissions | Unix permissions + ACL editor |
| Git Status | Repository status, branch, staged/unstaged changes |
| Processes | System process viewer with kill capability |
| Drop Stack | Temporary staging shelf for multi-step file moves |
| Tags | macOS tag management and star ratings |
| Bookmarks | Quick-access folder bookmarks bar |
| Disk Usage | Visual treemap of disk space consumption |
| Image Browser | Thumbnail grid for image-heavy folders |
| Search | Persistent search panel with saved queries |

## Keyboard & Navigation

- **Keyboard-first design**: every operation achievable without a mouse
- **Function key paradigm**: F3 view, F4 edit, F5 copy, F6 move, F7 mkdir, F8 delete (fully remappable)
- **Command palette** (Cmd+Shift+P) for fuzzy search across all actions
- **Optional Vim-style navigation** (hjkl + modal commands)
- **Global summon shortcut** (default: Ctrl+Space)

## Device & External Media

- **iOS device mounting** via USB for file browsing
- **MTP device support** (cameras, Android devices)
- **External drive management** with eject, format, and partition info

## Performance Targets

| Metric | Target |
|---|---|
| Cold launch to interactive | < 1 second |
| 10K file directory listing | < 100ms to first paint |
| 100K file directory listing | < 500ms, no scroll jank |
| Indexed search first result | < 50ms |
| Raw filesystem search first result | < 200ms |
| Terminal keystroke-to-echo (p95) | < 8ms |
| File copy throughput (local SSD) | > 90% of disk bandwidth |
| Memory idle (single tab) | < 80MB |

## Platform Integration

- **Native macOS**: AppKit + SwiftUI, no Electron or web views
- **System appearance**: Dark Mode, accent colors, accessibility (VoiceOver, reduced motion)
- **Drag and drop** integrates with Finder, Desktop, and other apps
- **Services menu**, Handoff, and standard macOS shortcuts
- **Keychain** for all remote credential storage
- **App Sandbox** for App Store distribution; notarized DMG for direct distribution
