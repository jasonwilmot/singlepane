# File Reader/Editor Applications Research for macOS

> Research compiled March 2026 for product development reference.
> Focus: Markdown, JSON, YAML, code, and structured data format handling.

---

## Key Market Statistics

- VS Code holds 65-70% market share among code editors; 75.9% usage in 2025 Stack Overflow survey (49,000+ respondents)
- Over 7,593 companies use VS Code globally; 50,000+ verified extensions in marketplace
- Obsidian has 1.5 million active users worldwide (2026); estimated $25M ARR; valued at $300-350M
- Sublime Text: $80 one-time purchase; GPU-accelerated rendering up to 8K resolution
- Zed opens a 50MB JS file in 0.8s vs VS Code's 3.2s; 75% lower memory usage than VS Code; smooth 60fps scrolling
- Code editor market growing; AI-native editors (Cursor, Windsurf) emerging as major category with $15-60/month pricing
- iA Writer: 2025 was its most commercially successful year; won Red Dot "Best of Best" award; Apple Design Award finalist

---

## 1. Markdown-Focused Editors

### Typora
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux |
| **Pricing** | $15 one-time purchase (free trial available) |
| **Killer Feature** | True inline WYSIWYG -- Markdown syntax disappears as you type, rendering in real-time within a single window. No split pane, no mode switching. |

**Markdown Handling:**
- Seamless live preview where Markdown syntax is rendered instantly as formatted text in the same editing surface
- Supports complex elements: tables, LaTeX math formulas, sequence charts, flowcharts via Mermaid
- No separate preview pane -- the editor IS the preview
- Multiple themes with full CSS customization
- Export to PDF, HTML, Word, and other formats

**UX Patterns Worth Studying:**
- The "disappearing syntax" model: when you type `**bold**`, it immediately renders as **bold** and hides the asterisks
- Cursor placement reveals the underlying Markdown when you click into formatted text
- This is the gold standard for "inline WYSIWYG" Markdown editing
- Minimal, distraction-free interface with no toolbar clutter

**Structured Data:** Basic code block syntax highlighting. Not designed for JSON/YAML editing.

---

### Obsidian
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux, iOS, Android |
| **Pricing** | Free for personal use; $50/user/year commercial; Sync: $4-8/month; Catalyst: $25+ one-time |
| **Users** | 1.5 million active users worldwide (2026) |
| **Revenue** | ~$25M ARR; valued $300-350M |
| **Killer Feature** | Bidirectional linking and knowledge graph -- notes are interconnected nodes in a visual graph, not isolated files |

**Markdown Handling:**
- Live Preview mode that hides Markdown formatting syntax and renders embedded content inline
- Visual editor for Markdown tables with context menus
- Reading view for fully rendered output
- Source mode for raw Markdown editing
- Three distinct modes: Source, Live Preview, Reading

**JSON/YAML/Structured Data:**
- YAML frontmatter is a first-class concept (used for metadata on every note)
- Dataview/Datacore plugins treat notes as a queryable database using YAML frontmatter fields
- Code blocks with syntax highlighting for JSON, YAML, and 100+ languages

**Notable UX Patterns:**
- Plugin ecosystem is massive: top plugins include Excalidraw, Templater, Dataview, Tasks, Advanced Tables
- Canvas feature for spatial arrangement of notes and media
- Command palette (Cmd+P) for all actions -- discoverable, keyboard-first
- Graph view for visualizing note relationships
- CSS-based theming with full community theme marketplace
- Local-first, plain Markdown files on disk (no proprietary format)

---

### iA Writer
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, iOS, Android |
| **Pricing** | $49.99 macOS, $29.99 Windows, $19.99 iOS (one-time purchases, no subscription) |
| **Killer Feature** | Focus Mode + custom typography -- sentence/paragraph-level focus highlighting with purpose-built fonts |

**Markdown Handling:**
- Markdown-native: separates writing from formatting
- Focus Mode highlights current sentence or paragraph, fading everything else
- Export to PDF, Word, HTML, and other formats
- Content blocks for embedding other Markdown files

**Typography (Critical Differentiator):**
- Three custom-designed fonts: iA Writer Mono, iA Writer Duo, iA Writer Quattro
- Mono: fixed-width for coding/technical writing
- Duo: duospaced (hybrid monospace) for focused writing
- Quattro: proportional for polished documents
- Typography is central to the product identity and reading experience
- High-contrast black-on-white design optimized for readability

**Notable UX Patterns:**
- AI Authorship feature: your words in black/white, AI-generated text in color, other authors in subtle tones
- Wikilinks for cross-referencing documents
- Minimal interface -- almost no chrome, content fills the window
- Style check highlights adjectives, adverbs, and filler words in different colors
- 14-day free trial with full functionality, no sign-up required

**Structured Data:** Code block support only. Not designed for structured data editing.

---

### Bear
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, iOS, iPadOS, Apple Watch |
| **Pricing** | Free (limited); Pro: $2.99/month or $29.99/year (14-day trial) |
| **Killer Feature** | Tag-based organization with nested hashtags + beautiful Markdown rendering |

**Markdown Handling:**
- Flexible Markdown editing with inline rendering that hides syntax for clean reading
- Formatting options: bold, italics, tables, links all rendered inline
- 12+ writing themes for visual variety
- Export to Markdown, HTML, PDF, DOCX, JPG, RTF
- Copy as Markdown, HTML, rich text, or plain text
- Backlinks support between notes

**Notable UX Patterns:**
- Hashtag-based organization (#tag/subtag for nested hierarchies) instead of folders
- Three-column layout: sidebar (tags) / note list / editor
- Focus mode for distraction-free writing
- Full inline image support
- Apple ecosystem integration: iCloud sync, Apple Watch app
- Clean, native macOS aesthetic

**Structured Data:** Limited. Code blocks with basic highlighting. Not a structured data tool.

---

### Marked 2
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | ~$14 (Mac App Store) |
| **Killer Feature** | Preview-only renderer that works alongside ANY text editor -- it watches your file and re-renders on save |

**Markdown Handling:**
- Two built-in Markdown processors: MultiMarkdown and Discount
- 9 handmade preview styles; fully customizable via CSS
- Markdown syntax checking and normalization across flavors
- Detects and highlights syntax errors it cannot normalize
- Tracks included files and updates previews automatically
- Export to HTML (self-contained with embedded images), Rich Text, PDF, OPML

**Notable UX Patterns:**
- Companion tool model: pairs with any editor (Typora, BBEdit, VS Code, etc.)
- Writing analysis tools: readability scores, word frequency, complexity metrics
- Typography-focused: layout and typography settings in preferences
- Code block text wrapping controlled by theme settings
- Fast change detection and preview updating

**Structured Data:** Renders code blocks with syntax highlighting. Not an editor for structured data.

---

## 2. Code/Text Editors with Strong Preview

### Visual Studio Code (VS Code)
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux |
| **Pricing** | Free and open source |
| **Market Share** | 65-70% of code editors; 75.9% in 2025 Stack Overflow survey |
| **Users** | 7,593+ companies; 50,000+ extensions |
| **Killer Feature** | Extensibility -- the marketplace ecosystem makes it handle virtually any file format |

**Markdown Handling:**
- Built-in Markdown support with side-by-side preview (Cmd+Shift+V to open preview, Cmd+K V for split)
- Syntax highlighting for Markdown source
- Extensions: "Markdown All in One," "Markdown Preview Enhanced," "Markdown Preview Github Styling"
- Preview scrolls in sync with editor
- Extensions add math typesetting, diagrams (Mermaid), emoji, superscript, task lists

**JSON/YAML/Structured Data:**
- Built-in JSON validation, formatting (Shift+Alt+F), and IntelliSense
- JSON schema validation with auto-detection
- Built-in YAML support with extensions (YAML by Red Hat) adding schema validation
- Outline view shows JSON/YAML structure in sidebar
- Folding for nested structures
- Breadcrumb navigation for deep nesting

**Syntax Highlighting:**
- TextMate grammar-based highlighting (`.tmLanguage` files)
- Semantic highlighting via Language Server Protocol (LSP)
- Injection grammars for embedded languages (e.g., JSON inside Markdown code blocks)
- Customizable themes (thousands available)

**Notable UX Patterns:**
- Command Palette (Cmd+Shift+P) -- the definitive implementation
- Split editors, tabs, panel system
- Integrated terminal
- Built-in Git integration
- Settings UI + settings.json duality
- Extension-driven architecture means any gap can be filled
- Minimap for code overview

**Performance:** Good for most files; can struggle with files >50MB. Preview refresh can slow on very large Markdown documents.

---

### Sublime Text 4
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux |
| **Pricing** | $80 one-time (free unlimited evaluation with nag dialog) |
| **Killer Feature** | Raw speed -- opens instantly, handles large files effortlessly, GPU-accelerated rendering |

**Markdown Handling:**
- Syntax highlighting for Markdown built-in
- No built-in preview; packages like "MarkdownPreview" and "MarkdownLivePreview" add preview capability
- Package "Markdown Editing" enhances editing experience with better syntax scopes and key bindings

**JSON/YAML/Structured Data:**
- Built-in JSON syntax highlighting and validation
- Pretty Print / reformat JSON via command palette
- YAML syntax highlighting (built-in but has had edge case issues)
- "Pretty YAML" package for formatting
- Packages: "SublimeLinter-json" for validation

**Syntax Highlighting:**
- Custom `.sublime-syntax` format AND `.tmLanguage` compatibility
- Non-deterministic grammar handling, multi-line constructs, lazy embeds, syntax inheritance
- Significantly improved engine in v4
- GPU-accelerated rendering up to 8K resolution with lower power consumption

**Notable UX Patterns:**
- Goto Anything (Cmd+P): file, symbol, and line navigation in one shortcut
- Multiple cursors and selections
- Minimap for document overview
- Distraction-free mode (full-screen, no chrome)
- Package Control ecosystem (thousands of community packages)
- Command palette

**Performance:** Best-in-class for raw text editing speed. Improved handling of files with very long lines in v4. GPU rendering provides fluid UI at all resolutions.

---

### Nova (by Panic)
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | $99 first year, $49/year renewal (optional; perpetual license after purchase). 30-day free trial. |
| **Killer Feature** | Native macOS design -- feels like an Apple-built app. Built-in web server with live preview. |

**Markdown Handling:**
- Syntax highlighting for Markdown
- No built-in Markdown preview renderer (extensions available)
- Focus on web development preview (HTML/CSS/JS live preview in built-in browser)

**JSON/YAML/Structured Data:**
- Syntax highlighting and autocomplete for JSON
- Built-in support for 20+ languages including JSON and YAML
- Extensions expand language support

**Syntax Highlighting:**
- Built-in syntax highlighting for CSS, HTML, JavaScript, Python, Ruby, PHP, TypeScript, and 20+ languages
- Tree-sitter based parsing for accurate highlighting
- Extensible via Nova extensions

**Notable UX Patterns:**
- Native macOS aesthetic: sidebar, inspector, integrated terminal
- Built-in local web server with live browser preview
- Emmet support built-in
- Task automation (build, run, clean)
- Extension marketplace
- FTP/SFTP integration
- Git integration
- Customizable toolbar and sidebar modules

**Performance:** Excellent. Native Swift/AppKit application with no Electron overhead.

---

### BBEdit
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | $59.99 purchase or $4.99/month ($49.99/year) Mac App Store subscription. Upgrades: $29.99-$39.99. |
| **Current Version** | 15.5 (May 2025) |
| **Killer Feature** | Grep/regex-powered find & replace across files -- the most powerful text search in any editor |

**Markdown Handling:**
- Syntax highlighting for Markdown
- No built-in Markdown preview (pairs well with Marked 2)
- Strong text manipulation tools useful for Markdown authoring

**JSON/YAML/Structured Data:**
- Syntax highlighting for JSON and YAML
- Powerful grep-based find/replace for transforming structured data
- Multi-file search and replace across projects
- Code folding for nested structures

**Syntax Highlighting:**
- Language modules for numerous languages
- Code folding support
- Extensible language support

**Notable UX Patterns (v15.5):**
- New "Workspaces" feature for switching between working environments
- macOS Writing Tools integration (Apple Intelligence summarization, proofreading)
- FTPS support
- Enhanced Git UX
- Handles large files without performance issues (3MB+ files verified)
- Scriptable: Python, Ruby, Perl, PHP, UNIX shell, AppleScript
- 30+ year legacy of reliability and stability

**Performance:** Excellent with large files. Massive pile of performance improvements in v15.5.

---

### CotEditor
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | Free and open source (Swift, native macOS) |
| **Killer Feature** | Lightweight, native, free -- the "TextEdit replacement" for developers |

**Markdown Handling:**
- Markdown syntax highlighting (pre-installed)
- No built-in Markdown preview
- Split window panes to see different parts of same document

**JSON/YAML/Structured Data:**
- Syntax highlighting for JSON and YAML among 50+ pre-installed languages
- Custom syntax definitions supported
- ICU regular expression engine for find/replace

**Syntax Highlighting:**
- 50+ pre-installed language definitions
- Custom syntax highlighting definitions
- Auto-indentation support

**Notable UX Patterns:**
- Pure native macOS application written in Swift
- Split editor panes
- Scriptable: Python, Ruby, Perl, PHP, UNIX shell, AppleScript as macro languages
- Handles CJK languages well
- Lightweight footprint
- Tabbed documents

**Performance:** Optimized for large files; slight slowdown on extremely large documents. Very low resource consumption.

---

### Zed
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Linux (Windows support added) |
| **Pricing** | Free and open source |
| **Killer Feature** | Speed -- Rust-based architecture with GPU rendering. 10x faster startup than VS Code. |

**Performance Benchmarks (vs VS Code):**
| Metric | Zed | VS Code |
|--------|-----|---------|
| Opening 50MB JS file | 0.8s | 3.2s |
| Syntax highlighting | 0.3s | 1.8s |
| Scrolling | Smooth 60fps | Occasional stutters |
| Memory usage | 75% lower | Baseline |

**Markdown Handling:**
- Syntax highlighting for Markdown
- Built-in Markdown preview
- Inline rendering capabilities

**JSON/YAML/Structured Data:**
- Syntax highlighting for JSON, YAML, and many other languages
- Tree-sitter based parsing

**Syntax Highlighting:**
- Parallel processing for syntax highlighting (background threads)
- Tree-sitter based parsing for accurate, incremental highlighting
- HTML character reference highlighting in TSX, JS, HTML
- Go definition highlights for functions, methods, types

**Notable UX Patterns:**
- Built by original Atom creators
- Real-time collaboration built-in
- AI integration (LLM-powered assistance)
- Direct-to-display rendering on macOS bypasses compositing for lower GPU load
- Idle GPU usage minimized: only presents frames during active input
- Terminal integration
- Multi-cursor support
- Command palette

**Architecture Notes for Reference:**
- Rust-based with GPUI (custom GPU-accelerated UI framework)
- Background threads for syntax highlighting, indexing, diagnostics
- UI thread remains completely fluid and responsive
- This is the closest architectural model to Velocity's performance goals

---

### TextMate 2
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | Free and open source (GPL-3.0) |
| **Killer Feature** | Bundle system -- declarative, extensible packages for any language/workflow |

**Markdown Handling:**
- Markdown bundle with syntax highlighting and snippets
- No built-in preview (extensions/bundles can add this)

**Syntax Highlighting:**
- Declarative bundle system: language grammars, snippets, macros, commands, templates
- `.tmLanguage` grammar format (became the industry standard -- used by VS Code, Sublime Text, and many others)
- Code folding via grammar definitions

**Notable UX Patterns:**
- Multiple insertion points (pioneered multi-cursor editing)
- Tab-triggered snippets
- Recordable macros
- Shell integration
- Folding sections
- Column selection

**Note:** TextMate's `.tmLanguage` grammar format became the de facto standard for syntax highlighting across the industry. VS Code, Sublime Text, and many others adopted it.

---

## 3. JSON/YAML-Specific Tools

### OK JSON
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only (native) |
| **Pricing** | Free 14-day trial; Pro: one-time purchase with lifetime updates |
| **Killer Feature** | Clean native macOS JSON viewer with jq and JSONPath support built-in |

**Features:**
- Tree view and text editor views
- Drag-and-drop support
- Dark Mode
- URL Schemes for automation
- Quick Look integration
- Built-in jq and JSONPath query support
- Viewing history saved to local database
- Custom script processing via JavaScriptCore
- Scriptable JSON formatting and transformation

---

### Dadroit JSON Viewer
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux |
| **Pricing** | Free (non-commercial); Standard: $98/year; Advanced: for files up to 1TB |
| **Killer Feature** | Handles massive JSON files (up to 1GB in seconds; Advanced license up to 1TB) |

**Features:**
- Treats JSON as a data format, not plain text
- Tree representation from root to deepest nodes
- Browse and query JSON like a DBMS
- Advanced RegEx and JSONPath searching
- Export to CSV, XML (formatted or minified)
- Auto-refresh when files change on disk
- Outstanding performance with massive files

---

### JSON Crack
| Attribute | Detail |
|-----------|--------|
| **Platform** | Web-based (cross-platform) |
| **Pricing** | Free, open source |
| **Killer Feature** | Visual graph representation of JSON/YAML/CSV/XML data |

**Features:**
- Transforms JSON, YAML, CSV, XML, TOML into visual graphs
- Tree view and graph view for data exploration
- Format conversion between data formats
- JSON formatting and validation
- Automatic code generation from data structures

---

### Smart JSON Editor
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS only |
| **Pricing** | Paid (Mac App Store) |
| **Killer Feature** | JSON tree editor with value transformers and integrated HTTP server |

**Features:**
- Intuitive JSON tree interface for visual editing
- Value transformers for streamlined data modification
- Integrated HTTP server for testing JSON APIs
- Create, edit, and manage complex JSON data structures

---

## 4. File Preview Utilities (Quick Look Ecosystem)

### Peek
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS (Quick Look extension) |
| **Pricing** | Paid (Mac App Store) |
| **Killer Feature** | Enhanced Quick Look for 300+ file extensions with copy, search, and syntax highlighting |

**Features:**
- Copy and find text within Quick Look previews
- Jump to line numbers and pages
- Render GitHub-flavored Markdown with auto-generated table of contents
- Restore scroll positions between previews
- Syntax highlighting for code files
- 300+ supported file extensions

---

### Glance
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS (Quick Look extension) |
| **Pricing** | Free (Mac App Store) |
| **Killer Feature** | Free Quick Look Markdown/code preview using Apple's swift-markdown library |

**Features:**
- Markdown preview in Quick Look using Apple's swift-markdown parser
- Converts Markdown to styled HTML, renders in lightweight WebView
- Supports .cpp, Python, Jupyter Notebooks, Markdown, tar/zip/gzip files
- Native macOS integration

---

### QLMarkdown
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS (Quick Look extension) |
| **Pricing** | Free, open source |
| **Killer Feature** | Broad Markdown-adjacent format support: .rmd, .mdx, .mdc, .qmd, .apib, textbundle |

**Features:**
- Previews Markdown files in Quick Look
- Also supports: R Markdown (.rmd), MDX (.mdx), Cursor Rulers (.mdc), Quarto (.qmd), API Blueprint (.apib), textbundle packages
- Configurable rendering options

---

### PreviewMarkdown / PreviewJson
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS (Quick Look extensions) |
| **Pricing** | Free, open source |
| **Killer Feature** | Separate focused extensions for Markdown and JSON Quick Look previews |

**Features:**
- PreviewMarkdown: Quick Look Markdown preview for macOS Big Sur+
- PreviewJson: Quick Look JSON preview with icon thumbnailing
- Both support Finder preview pane integration

---

### Markdown Peek
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS |
| **Pricing** | Paid |
| **Killer Feature** | Fastest Markdown Quick Look preview with GitHub-style formatting |

**Features:**
- Native Quick Look extension
- Instant rendering with GitHub-style formatting
- Optimized for speed

---

## 5. Emerging & Notable Tools (2025-2026)

### Cursor
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux (VS Code fork) |
| **Pricing** | $20/month Pro; $40/user/month Business (credit-based billing since June 2025) |
| **Killer Feature** | AI-first editor -- codebase-aware AI that can edit multiple files, refactor, and debug conversationally |

**Notable for Velocity team:** Cursor demonstrates that forking VS Code and adding a differentiated layer on top is a viable product strategy. The inline editing model (describe changes, AI rewrites) is a UX pattern worth studying.

---

### Windsurf (Codeium)
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, Windows, Linux (VS Code fork) |
| **Pricing** | Free (25 credits/month); Pro: $15/month (500 credits); Teams: $30/user/month; Enterprise: $60/user/month |
| **Killer Feature** | Cascade -- agentic AI that autonomously understands codebase, suggests multi-file edits, runs terminal commands |

**Notable:** Acquired by Cognition AI (creators of Devin) in December 2025. Aiming to create "first fully AI-driven development environment by late 2026."

---

### iPreview
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS |
| **Killer Feature** | Enhanced file preview directly from Finder/Spotlight for code, images, documents, multimedia |

---

### macOS 26 Preview (Apple)
| Attribute | Detail |
|-----------|--------|
| **Platform** | macOS, iOS 26, iPadOS 26 (new) |
| **Killer Feature** | At WWDC 2025, Apple announced Preview coming to iPhone/iPad. Signals increased investment in file preview capabilities across the platform. |

---

## 6. UX Patterns & Design Insights for Velocity

### Edit/Preview Mode Switching Patterns

There are three dominant paradigms in 2026:

| Pattern | Example Apps | Pros | Cons |
|---------|-------------|------|------|
| **Inline WYSIWYG** | Typora, Bear | No mode switching; natural feel; content-focused | Complex to implement; cursor behavior tricky; hard to edit raw syntax |
| **Split Pane** | VS Code, MacDown, StackEdit | See source and output simultaneously; familiar to developers | Splits attention; tiring for long sessions; wastes horizontal space |
| **Toggle/Tab** | Obsidian (Live Preview/Reading/Source), GitLab | Clean single view; user chooses when to preview | Context switch required; cognitive load of mode awareness |

**Recommendation for Velocity's built-in viewer:**
- For the F3 viewer (read-only), use rendered preview with syntax highlighting
- For inline editing, consider a hybrid: render Markdown inline (Typora-style) but allow toggling to raw source
- For JSON/YAML, use a collapsible tree view alongside formatted text

### Typography Best Practices

| App | Font Strategy | Result |
|-----|--------------|--------|
| iA Writer | 3 custom-designed fonts (Mono, Duo, Quattro) | Industry-leading readability; brand identity through typography |
| Bear | 12 built-in themes with curated font choices | Variety without overwhelming; each theme feels cohesive |
| Typora | Theme-based with CSS customization | Maximum flexibility; community themes add variety |
| Obsidian | Customizable; ships with Inter as default | Extensible; community themes |

**Recommendation:** Ship with 2-3 carefully chosen fonts: a monospace for code/hex, a proportional for Markdown/document preview, and optionally a duospace for hybrid content. Allow CSS/theme customization for power users.

### Performance Benchmarks to Target

Based on competitor analysis:

| Operation | Best-in-Class Benchmark | App |
|-----------|------------------------|-----|
| Opening 50MB file | 0.8 seconds | Zed |
| Syntax highlighting 50MB file | 0.3 seconds | Zed |
| Scrolling large files | 60fps smooth | Zed, Sublime Text |
| Opening 1GB JSON | Seconds (not minutes) | Dadroit |
| Markdown preview render | Instant (< 50ms) | Typora |
| Editor startup | < 1 second | Zed, Sublime Text |

### Syntax Highlighting Architecture

| Approach | Used By | Pros | Cons |
|----------|---------|------|------|
| TextMate grammars (.tmLanguage) | VS Code, Sublime Text, TextMate | Industry standard; huge library of grammars; well-understood | Regex-based; can be slow; limited accuracy |
| Tree-sitter | Zed, Nova, Neovim | Incremental parsing; accurate; fast | Newer; fewer grammars; more complex integration |
| Custom engine | Sublime Text (.sublime-syntax) | Optimized for performance; richer features | Proprietary; less ecosystem |

**Recommendation for Velocity:** Use Tree-sitter for syntax highlighting. It provides incremental parsing (only re-parse what changed), is accurate for nested languages, and performs well in background threads -- aligning with Velocity's off-main-thread architecture.

---

## 7. Pricing Landscape Summary

| App | Model | Price | Platform |
|-----|-------|-------|----------|
| VS Code | Free | $0 | Cross-platform |
| Zed | Free/Open Source | $0 | macOS, Linux |
| CotEditor | Free/Open Source | $0 | macOS |
| TextMate 2 | Free/Open Source | $0 | macOS |
| Obsidian | Freemium | $0 personal / $50/user/yr commercial | Cross-platform |
| Bear | Subscription | $2.99/mo or $29.99/yr | Apple ecosystem |
| Typora | One-time | $15 | Cross-platform |
| Marked 2 | One-time | ~$14 | macOS |
| iA Writer | One-time | $49.99 macOS | Cross-platform |
| BBEdit | Purchase or Sub | $59.99 or $4.99/mo | macOS |
| Sublime Text 4 | One-time | $80 | Cross-platform |
| Nova | Annual | $99 first yr / $49 renewal | macOS |
| Cursor | Subscription | $20/mo Pro | Cross-platform |
| Windsurf | Freemium | $0-$60/user/mo | Cross-platform |
| OK JSON | One-time | Pro license (price varies) | macOS |
| Dadroit | Annual | $98/yr Standard | Cross-platform |

---

## 8. Key Takeaways for Velocity's Built-in Viewer/Editor

1. **Markdown Preview:** Typora's inline WYSIWYG is the UX gold standard. For a file manager's viewer (F3), rendered Markdown preview with GitHub-style CSS is the minimum expectation. Consider supporting multiple preview styles.

2. **JSON/YAML Viewing:** A collapsible tree view (OK JSON / Dadroit model) is essential. Support jq/JSONPath queries for power users. Handle files up to 1GB without choking -- Dadroit proves this is achievable.

3. **Syntax Highlighting:** Use Tree-sitter for accuracy and performance. Support at minimum the top 20 languages. Pre-install grammars for: Markdown, JSON, YAML, XML, HTML, CSS, JavaScript, TypeScript, Python, Ruby, Swift, Go, Rust, Shell, SQL, C, C++, Java, PHP, TOML.

4. **Typography:** Invest in font selection. A carefully chosen monospace font (e.g., SF Mono, JetBrains Mono, or custom) dramatically impacts perceived quality. Consider a proportional font for Markdown preview rendering.

5. **Performance Bar:** Zed sets the standard. If Velocity's viewer can open and highlight a 50MB file in under 1 second with 60fps scrolling, it will be best-in-class.

6. **Mode Switching:** For a file manager context, default to read-only preview (rendered Markdown, formatted JSON tree, syntax-highlighted code). Allow an "Edit" toggle that switches to raw text editing. This is simpler than a full editor and appropriate for the use case.

7. **Quick Look Integration:** Consider implementing a Quick Look extension as a bonus -- it extends Velocity's preview capabilities to Finder, Spotlight, and system-wide file previews.

---

## Sources

- [Typora](https://typora.io/)
- [Obsidian](https://obsidian.md/pricing)
- [Obsidian Usage Statistics](https://fueler.io/blog/obsidian-usage-revenue-valuation-growth-statistics)
- [iA Writer](https://ia.net/writer)
- [iA Writer Features](https://ia.net/writer/support/basics/features)
- [Bear](https://bear.app/)
- [Marked 2](https://marked2app.com/)
- [VS Code Markdown](https://code.visualstudio.com/docs/languages/markdown)
- [VS Code Market Share](https://6sense.com/tech/ides-and-text-editors/visual-studio-code-market-share)
- [Sublime Text](https://www.sublimetext.com/)
- [Nova by Panic](https://nova.app/)
- [BBEdit](https://www.barebones.com/company/press/bbedit155_pr.html)
- [CotEditor](https://coteditor.com/)
- [Zed Editor](https://zed.dev/)
- [Zed vs VS Code Benchmarks](https://markaicode.com/zed-editor-vs-vscode-2025-performance-migration/)
- [TextMate](https://macromates.com/)
- [OK JSON](https://okjson.app/)
- [Dadroit JSON Viewer](https://dadroit.com/)
- [JSON Crack](https://jsoncrack.com)
- [Smart JSON Editor](http://www.smartjsoneditor.com/)
- [Peek Quick Look](https://www.bigzlabs.com/peek.html)
- [Glance](https://github.com/tokenpowered/glance)
- [QLMarkdown](https://github.com/sbarex/QLMarkdown)
- [PreviewJson](https://github.com/smittytone/PreviewJson)
- [Markdown Peek](https://markdownpeek.com/)
- [Cursor](https://www.cursor.com/)
- [Windsurf](https://windsurf.com/)
- [Quick Look Plugins List](https://github.com/sindresorhus/quick-look-plugins)
- [Modern Quick Look Extensions](https://github.com/Oil3/List-of-modern-Quick-Look-extensions)
- [DevOpsSchool Markdown Editors Comparison](https://www.devopsschool.com/blog/top-10-markdown-editors-in-2025-features-pros-cons-comparison/)
- [Best JSON Editors for Mac](https://www.merge-json-files.com/blog/best-json-editor-for-mac)
