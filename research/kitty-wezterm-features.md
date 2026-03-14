# Kitty & WezTerm Feature Research: What Users Actually Love

> Research conducted March 2026. Sources: Reddit (r/commandline, r/unixporn, r/neovim, r/linux), HackerNews, GitHub Discussions, blog posts, and comparison articles. Focus on real user sentiment.

---

## Table of Contents

1. [Kitty Terminal - What Users Love](#1-kitty-terminal---what-users-love)
2. [Kitty - What Frustrates Users](#2-kitty---what-frustrates-users)
3. [WezTerm - What Users Love](#3-wezterm---what-users-love)
4. [WezTerm - What Frustrates Users](#4-wezterm---what-frustrates-users)
5. [Head-to-Head Comparison](#5-head-to-head-comparison)
6. [SwiftTerm Baseline Capabilities](#6-swiftterm-baseline-capabilities)
7. [Recommendations for Velocity's Embedded Terminal](#7-recommendations-for-velocitys-embedded-terminal)
8. [Sources](#8-sources)

---

## 1. Kitty Terminal - What Users Love

### 1.1 Performance Architecture (Highly Praised)

Kitty's performance is the single most praised aspect across all forums. Users consistently describe it as "blazing fast" and one developer noted it's "the only software (besides Sublime) I run on my laptop that actually feels like it's using the 40 years of transistor improvements."

**Technical details users appreciate:**

- **VRAM Glyph Caching**: Kitty keeps a cache of every rendered glyph in video RAM (GPU texture memory as a sprite cache). Screen updates require only a few bytes sent to the GPU per refresh. This eliminates font rendering as a bottleneck entirely.
- **SIMD Byte Stream Parsing**: The incoming byte stream from child processes is parsed using vector CPU instructions (SIMD). This is significantly faster than character-by-character parsing used by most terminals.
- **Threaded Rendering**: Child process I/O happens on a separate thread from rendering. The display never stalls waiting for process output, and process output never stalls waiting for screen paint.
- **Benchmarked Results**: ~134 MB/s throughput across ASCII, Unicode, CSI, and image data -- approximately 2x faster than GNOME Terminal (61.8 MB/s) and Alacritty (54 MB/s). Hardware-measured keyboard latency matches Apple Terminal.app for best-in-class on macOS.

**Relevance to Velocity**: These architectural patterns (VRAM glyph cache, threaded I/O separation, SIMD parsing) are directly applicable to our embedded terminal. SwiftTerm already separates I/O from rendering, but we should investigate whether glyph caching in Metal texture memory and SIMD escape sequence parsing could further reduce latency.

### 1.2 The Kittens Plugin System (Power User Favorite)

Kittens are small Python-based programs that leverage kitty's advanced terminal features. Users describe the customizability as "off the charts, especially the remote control feature and the kittens feature."

**Most-used built-in kittens (by user mentions):**

| Kitten | What It Does | User Sentiment |
|--------|-------------|----------------|
| **Hints** | Highlights clickable items (URLs, file paths, git hashes, IP addresses, line numbers) on screen. Press a shortcut, type a letter label, and the item is opened/copied/inserted. | Most praised kitten. "I can quickly checkout git commits using hash options, and retrieve file paths, URLs" |
| **SSH** | Copies shell config, terminfo, and environment to remote hosts automatically. Makes remote shells feel identical to local. | Solves the #1 kitty complaint (terminfo issues) |
| **Diff** | Side-by-side file diff with syntax highlighting. Can diff images. Works over SSH. Under 3,000 lines of code. | "Fast side-by-side diff tool" -- appreciated for eliminating dependency on external diff viewers |
| **icat** | Display images inline in the terminal using the kitty graphics protocol. | Gateway feature that pulls people into the kitty ecosystem |
| **Unicode Input** | Browse and insert Unicode characters by name, hex code, or favorites list. ctrl+shift+u to activate. | "Unicode input menu" mentioned frequently as a convenience |
| **Themes** | Preview and hot-switch between 300+ color themes without restarting. | Quality of life feature users mention when recommending kitty |
| **Broadcast** | Type in one window and broadcast input to all/selected windows simultaneously. | Used for managing multiple SSH sessions or containers |
| **Custom Kittens** | Users can write their own kittens in Python with full access to kitty's API. | The extensibility mechanism power users build on |

**Relevance to Velocity**: The hints system is the standout feature for file manager integration. Imagine a user running `git status` in the embedded terminal, pressing a shortcut, and having all file paths highlighted with jump labels -- selecting one navigates the file browser to that file. The broadcast feature is useful for multi-terminal workflows.

### 1.3 Kitty Graphics Protocol (Growing Ecosystem)

The Kitty Graphics Protocol allows programs to transmit image data to the terminal for inline display. It has become the de facto standard for high-quality terminal graphics, now supported by multiple terminals (kitty, WezTerm, Ghostty).

**CLI tools that actively use it:**

- **File managers**: ranger, nnn, Yazi, clifm, hunter (all use it for file previews)
- **Image viewers**: viu, timg, term-image, koneko
- **Document viewers**: termpdf.py, tdf, fancy-cat, meowpdf, mdfried
- **Data visualization**: matplotlib (via kitcat and matplotlib-backend-kitty), gnuplot (kittygd/kittycairo backends), KittyTerminalImages.jl, k-nine (plotnine)
- **Developer tools**: onefetch (git repo info), neofetch (system info), euporie (Jupyter notebooks)
- **Neovim plugins**: image.nvim, snacks.nvim, image_preview.nvim, hologram.nvim
- **Web browsers**: awrit (Chromium-based), chawan, w3m
- **Media**: mpv (video playback in terminal)
- **Presentations**: presenterm, patat

**Adoption status**: Growing steadily. Graphviz added official support in v9.0.0. Microsoft Terminal has an open feature request. Zellij is in active discussion. The protocol is becoming a standard, not just a kitty-specific feature.

**Relevance to Velocity**: SwiftTerm already supports the Kitty Graphics Protocol, iTerm2 image protocol, and Sixel. This means our embedded terminal can already display inline images from tools like ranger, matplotlib, and Neovim image plugins. The file manager preview pane could pipe previews through the terminal for a unified experience, or the terminal could display file previews inline when users run `ls` or file inspection commands.

### 1.4 Shell Integration (Prompt Navigation)

Kitty's shell integration is deeply valued by daily users. It injects lightweight hooks into bash, zsh, and fish that enable:

- **Jump to previous/next prompt**: ctrl+shift+z / ctrl+shift+x. Navigate between commands in scrollback without manual scrolling.
- **View last command output in pager**: ctrl+shift+g. Opens the output of the most recent command in `less` for easy searching/copying.
- **Click to move cursor**: While editing a command at the prompt, click to reposition the cursor.
- **Prompt marking with OSC 133**: The standard protocol for semantic prompt marking. Also used by iTerm2, WezTerm, and Windows Terminal.

**Relevance to Velocity**: Prompt-to-prompt navigation is essential for a file manager's embedded terminal. When users run commands like `find`, `grep`, or `git log`, they need to quickly jump between outputs. The OSC 133 semantic zones also enable selecting entire command outputs with a single action.

### 1.5 Remote Control Protocol (Automation)

Kitty exposes a JSON-based IPC protocol that lets external scripts control the terminal:

- Open/close windows and tabs
- Send text to any window (by title, command, working directory, etc.)
- Change colors, fonts, and layouts programmatically
- Get window/tab state as JSON
- Scripted session management

Users leverage this for:
- Automated development environment setup scripts
- CI/CD dashboards that update terminal windows
- Custom tmux-like session management without tmux

**Relevance to Velocity**: A remote control API for the embedded terminal would enable the file manager to programmatically control terminal sessions. For example: user double-clicks a Makefile, the file manager opens a terminal tab, sends `make`, and streams output. Or: the search module finds a file and inserts its path into the active terminal prompt.

### 1.6 Keyboard Protocol (Progressive Enhancement)

Kitty designed a new keyboard protocol that's now being adopted by other terminals and terminal applications:

- Distinguishes between key press, repeat, and release events
- Disambiguates keys that traditional terminals conflate (e.g., Ctrl+I vs Tab)
- Progressive enhancement: applications opt-in to higher levels of key reporting
- Adopted by Neovim, Helix, foot, Rio, and other terminal apps

**Relevance to Velocity**: If the embedded terminal supports this protocol, terminal applications like Neovim running inside it would get proper key disambiguation. This matters for users who run vim/neovim inside the file manager's terminal.

### 1.7 Startup Sessions (Workspace Layouts)

Kitty allows defining session files that specify:
- Which tabs and windows to create
- What layout to use for each tab
- What command to run in each window
- What working directory to start in
- Environment variables to set

Users can save their current layout interactively and restore it later. Shell functions can launch project-specific sessions.

**Relevance to Velocity**: Terminal workspace presets that integrate with the file manager's layout system. User opens a "Web Development" workspace and gets: left pane on `src/`, right pane on `dist/`, bottom terminal split into `npm run dev` and `git log --oneline --watch`.

### 1.8 Built-in Multiplexing (Splits and Layouts)

Users value that kitty eliminates the need for tmux for local work:

> "Split open new windows and tabs in different layouts such as horizontal, vertical, stacked, grid, etc."
> "The configuration wasn't nearly as painful as with any terminal emulator I had before."

Kitty supports layout modes: tall, fat, grid, horizontal, vertical, splits, and stack. Each tab can have a different layout.

---

## 2. Kitty - What Frustrates Users

### 2.1 Terminfo / SSH Compatibility (Top Complaint)

The `xterm-kitty` terminfo entry doesn't exist on most remote servers. Users get "No entry for terminal type xterm-kitty; using dumb terminal settings" errors.

> "When I ssh into any of my servers, I get the errors described in the FAQ with regards to the terminfo files on the remote server."
> "You have to transfer terminfo to all ssh servers because the kitty term does not exist there."

The SSH kitten mitigates this, but it's an extra step and doesn't cover all workflows (e.g., jumping through bastion hosts).

### 2.2 Maintainer Communication (Drives Users Away)

This is the second most frequently mentioned frustration and has directly caused users to switch to WezTerm:

> "The straw that broke my back with using kitty was, I'd end up encountering issues... only to end up time and again on kitty's maintainer's terse and dismissive comments."
> "Kovid's arrogance pushed me away." -- hodapp, HackerNews
> "How do I set up tmux with kitty?" -> Maintainer response: "Don't, tmux is dumb."
> "He's just kind of mean, even when it makes no sense." -- saurik, HackerNews

Multiple HackerNews commenters independently cited this as their reason for leaving kitty.

### 2.3 macOS Rendering Quality Concerns

Some users find kitty's text rendering on macOS "dull compared to native macOS terminal" -- the GPU-based rendering can produce slightly different results than the native CoreText path used by Terminal.app and iTerm2.

### 2.4 No Bitmap Font Support

The developer intentionally refuses to add bitmap font support (e.g., Terminus), which limits options for users who prefer bitmap typefaces.

### 2.5 No Remote Session Persistence

Unlike tmux, there's no way to detach from a kitty session and reattach later. If the kitty process dies, all sessions are lost. This is a critical gap for users who SSH into remote machines.

### 2.6 Opinionated Design Choices

Kitty is described as "opinionated" -- the developer makes strong design decisions and is reluctant to add features that conflict with his vision. This is both a strength (coherent design) and frustration (users can't always customize to their needs).

---

## 3. WezTerm - What Users Love

### 3.1 Lua Configuration (Top Feature)

WezTerm's Lua-based configuration is consistently cited as its killer feature:

> "Its use of Lua for defining config... unlocks a ton of possibilities."
> "Lua can be picked up very quickly if you've used basically any programming language at all."
> "One thing that's absolutely magical is that I don't ever have to think about whether or not I've started tmux."

**What users build with Lua scripting:**

- **Dynamic theming**: Auto-switch light/dark mode based on OS appearance or time of day
- **Custom status bars**: Powerline-style bars showing workspace name, git branch, hostname, battery level, with dynamically generated color gradients
- **Workspace switchers**: Project-based workspace management with fuzzy search (smart_workspace_switcher.wezterm plugin)
- **Leader key systems**: tmux-style leader key (e.g., Ctrl+A) with chained keybinding trees
- **Conditional configuration**: Different settings per OS, per hostname, per project
- **Tab naming and formatting**: Custom tab title logic showing process name, working directory, or custom labels
- **Event handlers**: Respond to terminal events (window resize, tab change, content updates) with Lua callbacks
- **Session persistence**: Save/restore workspace layouts with wezterm-session-manager

**Hot reload**: Changes to `wezterm.lua` apply instantly without restarting. Combined with a built-in Lua REPL (Ctrl+Shift+L), this creates a "wonderfully tight feedback loop."

**Relevance to Velocity**: The Lua scripting model shows strong demand for terminal customization beyond static config files. For our embedded terminal, exposing a Swift-native event/callback system that integrates with the file manager would be more appropriate than Lua, but the use cases (dynamic theming, status bar, conditional behavior) are directly applicable.

### 3.2 Built-in Multiplexing (Replaces tmux for Many Users)

WezTerm's multiplexing is the second most praised feature:

> "Switching to WezTerm has completely eliminated the need for tmux for me."
> "WezTerm comes out of the box with the notion of windows and panes, the ability to split horizontally or vertically and most of the features that would be missed from leaving tmux."

**Key multiplexing features:**
- Tabs, panes (horizontal and vertical splits), resize, swap, zoom
- Workspaces: named groups of windows/tabs/panes for project isolation
- Unix domain sockets for persistent sessions (attach/detach like tmux)
- SSH domains: auto-populate from `~/.ssh/config`, with both plain SSH and multiplexed SSH modes
- Per-pane scrollback buffers
- Better mouse control and selection than tmux

**tmux migration path**: Windows, panes, and prefix keys map almost 1:1 from tmux to WezTerm concepts. Users who bring their tmux keybinds report smooth transitions.

**Limitations vs tmux**: Session persistence requires explicit setup (Unix domain sockets). Not as effortless as tmux's default behavior. Documentation for multiplexing is less beginner-friendly than tmux's.

**Relevance to Velocity**: Built-in multiplexing is essential for our embedded terminal. Users expect to split terminals without tmux. The workspace concept maps well to file manager workspace presets.

### 3.3 Quick Select Mode (Loved by Power Users)

WezTerm's Quick Select (Ctrl+Shift+Space) is a fast way to grab text from terminal output:

- Automatically highlights URLs, file paths, git hashes, IP addresses, and numbers
- Each match gets a letter label -- type the letter to copy to clipboard
- Typing the UPPERCASE letter copies AND pastes the text
- Custom patterns can be added via `quick_select_patterns` config
- Similar to kitty's hints kitten but integrated at a deeper level

> "C-S-Space and type the letters that appear next to the item" -- described as one of WezTerm's standout features

**Copy Mode** (Ctrl+Shift+X): Vim-style cursor movement for selecting arbitrary text regions in scrollback. Press `v` to start selection, navigate with hjkl, copy with Ctrl+Shift+C.

**Relevance to Velocity**: Quick Select for the embedded terminal would enable: highlight a file path in `git diff` output, type one letter, and the file browser navigates there. This is a direct file-manager-to-terminal integration point.

### 3.4 Cross-Platform Consistency

> "My favorite and often overlooked feature is that wezterm is fully cross os, so if you work like me in Linux, macOS and Windows, then you can just learn wezterm and be done."

Users value having identical terminal behavior across all their machines. Config lives in dotfiles and is portable.

**Relevance to Velocity**: Not directly applicable (macOS only), but the principle of consistent behavior across contexts (embedded terminal, detached terminal window, fullscreen mode) is valuable.

### 3.5 SSH Client with Multiplexing

WezTerm has a built-in SSH client that goes beyond just launching `ssh`:

- Auto-populates SSH domains from `~/.ssh/config`
- Multiplexed SSH: spawns `wezterm-mux-server` on the remote host, connects via Unix socket
- Remote pane management feels like local panes
- Session persistence across network interruptions

> "In practice, multiplexing feels significantly faster than working through raw SSH."

**Relevance to Velocity**: For a file manager that connects to remote servers, having the terminal understand SSH context enables: browse remote files in file pane while running commands in terminal pane, with both sharing the same SSH connection and remote working directory.

### 3.6 Multi-Protocol Image Support

WezTerm supports three image display protocols simultaneously:
- **iTerm2 image protocol** (most widely supported)
- **Kitty Graphics Protocol** (highest quality, growing adoption)
- **Sixel** (legacy, widest compatibility)

This means any CLI tool that outputs images in any of these formats will work.

**Relevance to Velocity**: SwiftTerm already supports all three protocols. Our embedded terminal will work with the full ecosystem of image-producing CLI tools out of the box.

### 3.7 Maintainer Responsiveness (Strong Community Factor)

The WezTerm maintainer (Wez Furlong) is consistently praised as the opposite of kitty's:

> "Shockingly responsive to GitHub issues and usually fixes things... within a day or two."
> "He's struck the perfect tone in every single one."

Multiple users explicitly cited the maintainer's attitude as the reason they switched from kitty to WezTerm.

**Caveat (2025)**: Development has slowed significantly. The last official release was February 2024. Users must use nightly builds for latest features. There are open questions about the project's long-term future, with some users reporting crashes and stability issues.

### 3.8 Semantic Shell Integration / Zones

WezTerm supports OSC 133 semantic prompt escapes:
- Prompt, command input, and command output are tagged as distinct zones
- Triple-click selects an entire semantic zone (e.g., all output from one command)
- `ScrollToPrompt` action for jumping between prompts
- Zone-aware text selection

**Relevance to Velocity**: Semantic zones enable powerful file manager integration. Select the entire output of `find . -name "*.swift"` with one click, parse the paths, and show them in the file browser's search results.

---

## 4. WezTerm - What Frustrates Users

### 4.1 Memory Consumption (Top Complaint)

> "Memory and resource consumption is the greatest weakness of WezTerm."

- Baseline: ~170MB resident (vs ~80MB for Alacritty, ~50MB for Kitty)
- With WebGPU: ~320MB
- After extended use (18+ hours): reports of RSS growing to 1.4GB
- Memory leaks documented in multiple GitHub issues

### 4.2 Performance Compared to Kitty/Alacritty

> "Even though WezTerm has lots of options but it's slow compared to Kitty."

- Noticeably slower large-character redraws
- Higher CPU usage during Neovim scrolling
- Startup time: 0.347s vs Alacritty's 0.092s
- Input latency issues on Windows (less of a problem on macOS)
- Ghostty benchmarked as "2-5x more performant" depending on scenario

### 4.3 Lua Configuration Complexity

While praised by programmers, Lua config is a barrier for non-programmers:

> "Any modest customisation would result in a side quest to learn."
> "You can't perform that action at this time" -- documentation assumes prior knowledge of events, objects, etc.

The documentation gap is real -- multiplexing and domain concepts are poorly explained for beginners.

### 4.4 macOS-Specific Issues

- **Non-native font rendering**: Text doesn't look as crisp as native macOS apps
- **Keyboard shortcuts**: Don't match macOS conventions by default
- **Drag-and-drop**: Documented malfunctions
- **Dock integration**: Problems when using multiplexing
- **No hotkey window**: iTerm2's popular dropdown/floating terminal feature is missing

### 4.5 Line Wrapping Bug (Showstopper for Some)

> "When copying a line that gets wrapped, it includes a newline in the copied text. Very annoying."

This is especially problematic with tmux integration and has been called a "showstopper" by multiple users.

### 4.6 Missing Features

- No right-click context menu
- No drag-and-drop tab rearrangement
- Session recovery/persistence requires manual setup
- No broadcasting feature (kitty has this)
- Search improvements needed (auto-appends previous terms, can't search during streaming)

### 4.7 Development Pace (2025 Concern)

Last official release: February 2024. Users report increasing crashes on nightly builds. The maintainer appears to have reduced involvement, raising questions about the project's future.

---

## 5. Head-to-Head Comparison

| Feature | Kitty | WezTerm | Winner for Velocity |
|---------|-------|---------|-------------------|
| **Raw performance** | Fastest (134 MB/s throughput, VRAM caching, SIMD parsing) | Slower (~2-5x vs Ghostty), higher memory | Kitty's architecture |
| **Keyboard latency** | Best-in-class (matches Terminal.app) | Acceptable on macOS, issues on Windows | Kitty |
| **Memory usage** | ~50-80MB | ~170-320MB, leak-prone | Kitty |
| **Configuration** | Plain text (kitty.conf) -- simple but limited | Lua scripting -- powerful but complex | Depends on use case |
| **Extensibility** | Kittens (Python plugins) + remote control API | Lua scripting + event system + plugin ecosystem | WezTerm (more flexible) |
| **Multiplexing** | Built-in layouts (tall, fat, grid, splits, stack) | Full multiplexer with workspaces, domains, persistence | WezTerm (more complete) |
| **Image protocols** | Kitty Graphics Protocol (originator) | Kitty + iTerm2 + Sixel (broadest support) | WezTerm (breadth) |
| **Shell integration** | OSC 133, prompt jump, output capture | OSC 133, semantic zones, zone selection | Tie (both strong) |
| **SSH** | SSH kitten (transfers config to remote) | Built-in SSH client with multiplexing domains | WezTerm |
| **Text selection** | Hints kitten (URLs, paths, hashes, custom patterns) | Quick Select + Copy Mode (vim-style) | Tie (both excellent) |
| **Startup sessions** | Session files with interactive save/restore | Lua-defined workspaces with persistence | Kitty (simpler model) |
| **macOS integration** | Decent, some rendering complaints | Weaker, non-native feel | Kitty (slightly) |
| **Font rendering** | VRAM-cached, ligatures, no bitmap fonts | Ligatures, Nerd Font bundled, some inconsistencies | Tie |
| **Maintainer** | Technically brilliant, abrasive communication | Responsive and collaborative, but slowing down | WezTerm (community) |
| **Future stability** | Active development, opinionated but stable | Uncertain -- last release Feb 2024 | Kitty |
| **Broadcast input** | Yes (broadcast kitten) | No | Kitty |
| **Keyboard protocol** | Invented the progressive enhancement protocol | Supports kitty keyboard protocol | Kitty (originator) |

---

## 6. SwiftTerm Baseline Capabilities

SwiftTerm (the library Velocity uses) already supports many of the features users love:

**Already Supported:**
- Kitty Graphics Protocol (inline images)
- iTerm2 image protocol
- Sixel graphics
- TrueColor (24-bit color)
- 256-color palette
- Bold, italic, underline, strikethrough, dim text attributes
- Unicode rendering including emoji and combining characters
- OSC 8 hyperlinks
- Mouse events
- Selection engine
- Search functionality
- macOS AppKit NSView (native rendering)

**Gaps to Evaluate:**
- Shell integration (OSC 133 prompt marking) -- needs verification
- Kitty keyboard protocol (progressive enhancement) -- needs verification
- VRAM glyph caching (kitty-style GPU optimization) -- not documented
- SIMD byte stream parsing -- not documented
- Quick Select / hints mode -- not built-in
- Broadcast input -- not built-in
- Remote control API -- not built-in

---

## 7. Recommendations for Velocity's Embedded Terminal

### Tier 1: Must-Have (Highest User Value, Best File Manager Integration)

#### 7.1 Hints / Quick Select Mode
**What**: Press a shortcut to highlight all recognizable patterns (file paths, URLs, git hashes, line:column references) on screen with letter labels. Type a letter to act on the selection.

**Why**: This is the highest-value feature for a file manager terminal. The intersection of "terminal output" and "file navigation" is exactly where a file manager adds value that standalone terminals cannot.

**Actions on selection**:
- **Open in file browser**: Navigate the file pane to the selected path
- **Open in editor**: Open the file at the specified line number in the preview pane
- **Copy to clipboard**: Standard copy
- **Insert into terminal**: Paste the path into the active command line
- **Add to staging area**: Send the file to the Drop Stack module

**Implementation complexity**: Medium. Requires regex pattern matching against visible terminal buffer, overlay rendering of labels, and integration with file manager navigation.

#### 7.2 Shell Integration (OSC 133 Semantic Zones)
**What**: Integrate with bash/zsh/fish to mark prompts, commands, and output as semantic zones.

**Why**: Enables prompt-to-prompt jumping, one-click command output selection, and the ability for the file manager to understand what commands the user is running.

**Integration opportunities**:
- Jump between command outputs in scrollback
- Select entire command output with one click
- Parse `cd` commands to auto-navigate the file browser
- Parse `git status` output to highlight changed files in the file pane
- Show last command's exit status in the terminal tab title

**Implementation complexity**: Low-Medium. OSC 133 is a well-documented standard. SwiftTerm may already partially support it.

#### 7.3 Bidirectional Directory Sync
**What**: Terminal CWD and file browser CWD stay in sync, with user control over which leads.

**Why**: This is the #1 feature users cite when comparing file managers with embedded terminals. Captain's Deck, Dolphin, and Nemo all implement this. It's table stakes.

**Modes**:
- **File browser leads**: Navigate in file pane, terminal `cd`s automatically
- **Terminal leads**: Run `cd` in terminal, file pane navigates automatically
- **Independent**: No sync (for users who want decoupled views)
- **Lock toggle**: Quick shortcut to toggle sync on/off

**Implementation complexity**: Medium. Requires OSC 7 (current directory reporting) from shell integration and intercepting/injecting `cd` commands.

#### 7.4 Built-in Multiplexing (Splits and Tabs)
**What**: Split terminals horizontally/vertically, manage multiple terminal tabs, resize panes.

**Why**: Users of both kitty and WezTerm cite "replaces tmux" as a top reason for adoption. An embedded terminal without splits feels crippled.

**Layout modes** (inspired by kitty): horizontal, vertical, grid, stacked (tabbed within a pane), and user-draggable splits.

**Implementation complexity**: Medium-High. Requires managing multiple PTY sessions, layout engine for pane positioning, and keyboard shortcuts for navigation.

### Tier 2: High-Value (Differentiating Features)

#### 7.5 Inline Image Display
**What**: Display images, plots, and previews directly in terminal output.

**Why**: SwiftTerm already supports Kitty Graphics, iTerm2, and Sixel protocols. This means tools like matplotlib, ranger, viu, and timg will "just work." For a file manager, this means `ls` with image previews, inline chart rendering during data analysis, and rich command output.

**File manager integration**: When a user runs a command that produces image output, the terminal can display it inline. The file manager could also inject image previews when hovering over files in terminal output.

**Implementation complexity**: Low (SwiftTerm handles the protocols). Medium for file manager integration features.

#### 7.6 Drag-and-Drop Path Insertion
**What**: Drag files from the file browser into the terminal to insert shell-escaped paths at cursor position.

**Why**: Already in the Velocity spec. Users of both kitty and WezTerm mention drag-to-terminal as a key workflow. Multi-file drag should insert space-delimited paths. Modifier key for relative paths.

**Implementation complexity**: Low-Medium. Standard macOS drag-and-drop with shell escaping logic.

#### 7.7 Terminal-Aware File Previews
**What**: When hovering or selecting a file in terminal output (e.g., from `ls`, `find`, `git status`), show a preview tooltip or update the preview pane.

**Why**: Bridges the gap between terminal and GUI. No standalone terminal can do this -- it requires the file manager context.

**Implementation complexity**: High. Requires pattern matching against terminal content, mapping matched text to filesystem paths, and coordinating with the preview system.

#### 7.8 Broadcast Input
**What**: Type once, send to multiple terminal panes simultaneously.

**Why**: Kitty users love this for managing multiple SSH sessions. Useful for sysadmins running the same command across multiple servers.

**Implementation complexity**: Low. Route keyboard input to multiple PTY sessions.

### Tier 3: Nice-to-Have (Polish Features)

#### 7.9 Workspace/Session Presets
**What**: Save and restore terminal layouts with specific commands running in each pane.

**Why**: Users of both kitty (session files) and WezTerm (workspace system) value this. For a file manager, this means: open "Deploy" workspace and get terminal splits with `ssh prod1`, `ssh prod2`, and `tail -f /var/log/app.log`.

**Integration**: Tie into the file manager's existing workspace/layout save/restore system.

**Implementation complexity**: Medium.

#### 7.10 Smart Command Detection
**What**: The terminal recognizes certain commands and offers enhanced interactions.

**Why**: Unique to an embedded terminal in a file manager context.

**Examples**:
- Detect `git status` and offer to stage/unstage files via the Git module
- Detect `npm install` or `cargo build` and show progress in a status bar
- Detect `cd` and update breadcrumbs
- Detect file creation/deletion and trigger FSEvents-like refresh in file pane

**Implementation complexity**: High. Requires command parsing and integration with multiple file manager modules.

#### 7.11 Copy Mode (Vim-Style Text Selection)
**What**: Enter a mode where hjkl navigates the scrollback buffer and v starts selection, similar to WezTerm's copy mode.

**Why**: Power users want keyboard-only text selection in scrollback. Both kitty and WezTerm offer this.

**Implementation complexity**: Medium.

#### 7.12 Progressive Keyboard Protocol
**What**: Support the kitty keyboard protocol for enhanced key reporting to terminal applications.

**Why**: Neovim and Helix users running inside the embedded terminal benefit from disambiguated keys (e.g., Ctrl+I vs Tab).

**Implementation complexity**: Medium-High. Requires implementing the progressive enhancement escape sequences.

### Feature Priority Matrix

| Feature | User Demand | FM Integration Value | Implementation Effort | Priority |
|---------|-------------|---------------------|----------------------|----------|
| Hints/Quick Select | Very High | Very High | Medium | **P0** |
| Shell Integration (OSC 133) | High | Very High | Low-Medium | **P0** |
| Bidirectional Dir Sync | Very High | Very High | Medium | **P0** |
| Splits/Tabs Multiplexing | Very High | High | Medium-High | **P0** |
| Inline Image Display | High | High | Low | **P1** |
| Drag-Drop Path Insertion | High | Very High | Low-Medium | **P1** |
| Terminal-Aware File Previews | Medium | Very High | High | **P1** |
| Broadcast Input | Medium | Medium | Low | **P2** |
| Workspace Presets | Medium | High | Medium | **P2** |
| Smart Command Detection | Low | Very High | High | **P2** |
| Copy Mode (Vim-style) | Medium | Low | Medium | **P2** |
| Keyboard Protocol | Medium | Low | Medium-High | **P3** |

### What NOT to Build (Standalone Terminal Features That Don't Translate)

1. **Full SSH client with multiplexing domains**: WezTerm's SSH domain system is impressive but only makes sense for a standalone terminal. The file manager should handle remote connections at the file browsing level and provide a connected terminal, not the other way around.

2. **Lua/Python scripting configuration**: The embedded terminal should be configured through the file manager's settings UI, not a separate scripting language. The demand for Lua config in WezTerm reflects users wanting control that a file manager already provides through its module system.

3. **300+ bundled color themes**: The terminal should inherit the file manager's theme system, not maintain its own.

4. **Drop-down/quake-style terminal**: This is a standalone terminal UX pattern. The embedded terminal is always visible as a module in the file manager's layout.

5. **Extensive remote session persistence**: tmux-style detach/reattach is a standalone terminal concern. The file manager's workspace save/restore should handle terminal state as part of the overall layout.

---

## 8. Sources

### Primary Research Sources

- [Reddit Opinions on Kitty Terminal](https://crowdfavs.com/services/kitty-terminal)
- [HackerNews: Kitty GPU-based Terminal Emulator (2025)](https://news.ycombinator.com/item?id=45313417)
- [HackerNews: "Okay, I Like WezTerm" Discussion](https://news.ycombinator.com/item?id=41223934)
- [HackerNews: Switching from Kitty to WezTerm](https://news.ycombinator.com/item?id=41224245)
- [HackerNews: WezTerm Favorite Features](https://news.ycombinator.com/item?id=41224280)
- [GitHub Discussion: What Makes WezTerm Bad?](https://github.com/wezterm/wezterm/discussions/2999)
- [GitHub Discussion: Should I Switch to WezTerm from Kitty?](https://github.com/wezterm/wezterm/discussions/6159)
- [GitHub: WezTerm Development Status Concerns](https://github.com/wezterm/wezterm/issues/7451)

### Kitty Documentation & Technical Sources

- [Kitty Performance Architecture](https://sw.kovidgoyal.net/kitty/performance/)
- [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [Kitty Shell Integration](https://sw.kovidgoyal.net/kitty/shell-integration/)
- [Kitty Keyboard Protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
- [Kitty Remote Control](https://sw.kovidgoyal.net/kitty/remote-control/)
- [Kitty Integrations with Other Tools](https://sw.kovidgoyal.net/kitty/integrations/)
- [Kitty Hints Kitten](https://sw.kovidgoyal.net/kitty/kittens/hints/)
- [Kitty Diff Kitten](https://sw.kovidgoyal.net/kitty/kittens/diff/)
- [Kitty Broadcast Kitten](https://sw.kovidgoyal.net/kitty/kittens/broadcast/)
- [Kitty Sessions](https://sw.kovidgoyal.net/kitty/sessions/)
- [Kitty Overview](https://sw.kovidgoyal.net/kitty/overview/)

### WezTerm Documentation & User Sources

- [WezTerm Features](https://wezterm.org/features.html)
- [WezTerm Multiplexing](https://wezterm.org/multiplexing.html)
- [WezTerm SSH](https://wezterm.org/ssh.html)
- [WezTerm Shell Integration](https://wezterm.org/shell-integration.html)
- [WezTerm Quick Select Mode](https://wezterm.org/quickselect.html)
- [WezTerm Copy Mode](https://wezterm.org/copymode.html)
- [WezTerm Lua Config Reference](https://wezterm.org/config/lua/general.html)
- [Alex Plescan: "Okay, I Really Like WezTerm"](https://alexplescan.com/posts/2024/08/10/wezterm/)
- [mwop.net: How I Use WezTerm](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html)
- [WezTerm Session Management without tmux](https://fredrikaverpil.github.io/blog/2024/10/20/session-management-in-wezterm-without-tmux/)
- [Switching from tmux to WezTerm](https://www.florianbellmann.com/blog/switch-from-tmux-to-wezterm)
- [WezTerm Config with Zellij-style Layouts](https://gist.github.com/johnlindquist/e0c272d27919706a4a0b396b0a9e04aa)

### SwiftTerm

- [SwiftTerm GitHub Repository](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm Swift Package Index](https://swiftpackageindex.com/migueldeicaza/SwiftTerm)

### Comparison Articles

- [Modern Terminals Showdown: Alacritty, Kitty, and Ghostty](https://blog.codeminer42.com/modern-terminals-alacritty-kitty-and-ghostty/)
- [Choosing a Terminal on macOS (2025)](https://medium.com/@dynamicy/choosing-a-terminal-on-macos-2025-iterm2-vs-ghostty-vs-wezterm-vs-kitty-vs-alacritty-d6a5e42fd8b3)
- [Terminal Compatibility Matrix](https://tmuxai.dev/terminal-compatibility/)
- [Switching from Ghostty Back to Kitty](https://linkarzu.com/posts/terminals/ghostty-to-kitty/)
- [Best Linux Terminal in 2025](https://www.linuxnest.com/the-best-linux-terminals-in-2025-a-head-to-head-comparison/)
- [Mac File Manager Showdown 2025](https://tokie.is/blog/mac-file-manager-showdown-mid-2025-commander-one-forklift-path-finder-houdahspot-cyberduck-compared)
- [Mastering Kitty Terminal](https://paul-nameless.com/mastering-kitty.html)
- [Goodbye Kitty (Migration Story)](https://meanii.dev/posts/goodbye-kitty/)

### GPU Sprite Cache Deep Dive

- [GPU Sprite Cache and Texture Management (DeepWiki)](https://deepwiki.com/kovidgoyal/kitty/4.3-constants-and-runtime-settings)
