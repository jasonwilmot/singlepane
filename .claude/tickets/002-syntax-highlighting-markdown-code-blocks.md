# 002: Syntax Highlighting in Markdown Code Blocks

**Priority:** P1
**Effort:** Small
**Labels:** Feature, Preview
**Phase:** 1 — Must-Have

## Problem

Markdown preview renders fenced code blocks as plain monospace text with no coloring. Every competitor (VS Code, Obsidian, GitHub, Bear) applies syntax highlighting inside code blocks based on the language tag (e.g., ` ```swift `). We already have `CodeSyntaxHighlighter` with patterns for 25+ languages — we just need to apply it during HTML generation.

## Requirements

- Detect the language tag on fenced code blocks during Markdown → HTML conversion
- Apply syntax-aware CSS classes to tokens inside `<pre><code>` blocks
- Support all languages already in `CodeSyntaxHighlighter.language(for:)`
- Fall back to plain monospace when no language tag is specified or language is unrecognized
- Colors must come from the active theme (already have `.syn-comment`, `.syn-string`, `.syn-keyword`, `.syn-number`, `.syn-key` CSS classes in the HTML template)

## Implementation Notes

- `MarkdownPreviewViewController` already generates CSS classes for syntax colors but doesn't populate them in code blocks
- In the `HTMLConverter` (Markup → HTML), when visiting a `CodeBlock` node with a language attribute, run the code through a lightweight tokenizer that wraps tokens in `<span class="syn-keyword">` etc.
- Can reuse the regex patterns from `CodeSyntaxHighlighter.patterns(for:)` — apply them to generate HTML spans instead of NSAttributedString attributes
- Alternative: generate a static HTML highlight function in JavaScript that runs client-side in the WKWebView (e.g., embed highlight.js or Prism.js as a lightweight option)

## Files to Modify

- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — HTML generation
- `totalcommander/UI/Preview/CodeSyntaxHighlighter.swift` — expose patterns for HTML span generation

## Acceptance Criteria

- [ ] Fenced code blocks with language tags render with syntax highlighting in markdown preview
- [ ] All 25+ supported languages work
- [ ] Colors match the active theme
- [ ] Untagged code blocks render as plain monospace (no broken highlighting)
- [ ] Theme switching updates code block colors
