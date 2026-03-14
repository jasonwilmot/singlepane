# 006: Code Block Copy Button in Markdown Preview

**Priority:** P2
**Effort:** Small
**Labels:** Feature, Preview
**Phase:** 1 — Must-Have

## Problem

Markdown preview renders code blocks without a copy button. GitHub, Obsidian, VS Code preview, and virtually every modern markdown renderer include a "copy to clipboard" button on code blocks. Users frequently copy code snippets from documentation and config files.

## Requirements

- Add a copy button (clipboard icon) to the top-right corner of every `<pre><code>` block in markdown preview
- Button appears on hover over the code block
- Click copies the raw code content (no HTML formatting) to the system clipboard
- Brief visual feedback on copy (e.g., icon changes to checkmark for 1.5s, or "Copied!" tooltip)
- Button style should be subtle and theme-aware

## Implementation Notes

- Implement in JavaScript within the WKWebView HTML template
- Add a small `<button>` element positioned absolute within each `<pre>` block
- Use the Clipboard API (`navigator.clipboard.writeText()`) or fall back to `document.execCommand('copy')`
- Since WKWebView sandbox may restrict clipboard access, consider using `WKScriptMessageHandler` to send the text back to Swift and use `NSPasteboard` directly
- CSS: position absolute, top-right of `<pre>`, semi-transparent background, visible on `:hover`

## Files to Modify

- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — add JS + CSS to HTML template, add WKScriptMessageHandler for clipboard

## Acceptance Criteria

- [ ] Copy button appears on hover over any code block in markdown preview
- [ ] Clicking copies raw code text to clipboard
- [ ] Visual feedback confirms the copy
- [ ] Button is theme-aware (not jarring in dark/light themes)
- [ ] Works for code blocks with and without language tags
