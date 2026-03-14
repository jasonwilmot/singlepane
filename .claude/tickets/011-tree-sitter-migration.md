# 011: Migrate Syntax Highlighting to Tree-sitter

**Priority:** P2
**Effort:** Large
**Labels:** Improvement, Preview
**Phase:** 2 — Differentiator

## Problem

`CodeSyntaxHighlighter` uses simple regex patterns for syntax highlighting. This has several limitations:
- No multiline awareness (can mis-highlight across line boundaries)
- No incremental updates (full re-highlight on every edit, O(n) on file size)
- Limited accuracy (can't distinguish template strings from regular strings, no scope nesting)
- No support for embedded languages (e.g., CSS inside HTML, SQL inside Python strings)
- Can't power features like bracket matching, code folding, or symbol outlines

Tree-sitter is the industry standard used by Zed, Nova, and Neovim. It provides incremental parsing, accurate AST-based highlighting, and runs well on background threads — aligning with CLAUDE.md's off-main-thread architecture.

## Requirements

### Core
- Replace regex-based highlighting with Tree-sitter grammar-based parsing
- Incremental parsing: only re-parse the changed region on edit, not the entire file
- Background thread parsing with main-thread rendering (no UI jank)
- Support the same 25+ languages currently in `CodeSyntaxHighlighter`

### Quality
- Accurate scope-based coloring (e.g., distinguish function names from variable names)
- Embedded language support (CSS in HTML, JS in HTML, regex in strings)
- No mis-highlighting of multiline strings, comments, or template literals

### Performance
- Highlight a 50MB file in < 500ms (Zed achieves 300ms)
- Incremental re-highlight on edit: < 5ms
- Memory usage proportional to AST size, not file size
- 60fps scrolling during active highlighting

### Extensibility
- Tree-sitter grammars are declarative and community-maintained
- Adding a new language = adding a grammar file, not writing regex
- Foundation for future features: code folding, symbol outline, bracket matching

## Implementation Notes

- Use [SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter) — Swift wrapper around tree-sitter C library
- Or link tree-sitter C library directly via SPM/framework and write thin Swift wrappers
- Each language needs a compiled grammar (`.dylib` or statically linked)
- Bundle grammars for top 20 languages, load dynamically for others
- Highlight query files (`.scm`) define which AST nodes map to which highlight scopes
- Map scopes to our existing color indices (comment, string, keyword, number, key)
- Keep `CodeSyntaxHighlighter.language(for:)` extension mapping — just change what happens after detection
- Fallback: if no tree-sitter grammar exists for a language, fall back to current regex patterns

## Files to Create

- `totalcommander/Services/TreeSitterHighlighter.swift`
- `totalcommander/Services/TreeSitterLanguages.swift` (grammar loader)
- `Resources/TreeSitterGrammars/` (bundled grammar files)
- `Resources/TreeSitterQueries/` (highlight query `.scm` files)

## Files to Modify

- `totalcommander/UI/Preview/CodeSyntaxHighlighter.swift` — refactor to delegate to TreeSitter, keep regex as fallback
- `totalcommander/UI/Preview/CodePreviewViewController.swift` — use async highlighting
- `totalcommander/UI/Preview/EditorViewController.swift` — use incremental highlighting

## Acceptance Criteria

- [ ] All 25+ languages highlight correctly with Tree-sitter
- [ ] Multiline strings and comments highlight correctly
- [ ] Embedded languages highlight (CSS in HTML at minimum)
- [ ] Editing a 10,000-line file re-highlights in < 5ms
- [ ] 50MB file highlights in < 500ms
- [ ] No UI jank during highlighting (background thread)
- [ ] Regex fallback works for languages without Tree-sitter grammar
- [ ] Adding a new language requires only a grammar + query file
