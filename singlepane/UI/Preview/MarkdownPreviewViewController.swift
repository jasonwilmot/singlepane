// MarkdownPreviewViewController.swift
// Renders markdown files as styled HTML in a WKWebView.
// Uses Apple's swift-markdown parser for GitHub-flavored markdown support.
//
// The toolbar (Edit button) is owned by PreviewContainerViewController.
// This VC exposes scroll-to-heading and scroll spy for the outline column.

import AppKit
import UniformTypeIdentifiers
import WebKit
import Markdown

@MainActor
final class MarkdownPreviewViewController: NSViewController {

    // MARK: - Properties

    private let webView = WKWebView()

    /// The file currently being previewed.
    private(set) var currentFileURL: URL?

    /// Callback when user clicks a local folder link — navigates the file explorer.
    var onFolderLinkClicked: ((URL) -> Void)?

    /// Callback when user clicks a local file link — selects and previews the file.
    var onFileLinkClicked: ((URL) -> Void)?

    /// Callback when the visible heading changes during scrolling (scroll spy).
    /// Passes the heading anchor ID (e.g., "heading-42").
    var onVisibleHeadingChanged: ((String) -> Void)?

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        // WebView for rendered content — fills the entire container
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        webView.navigationDelegate = self
        container.addSubview(webView)

        // Set up message handlers for JavaScript → Swift callbacks
        webView.configuration.userContentController.add(
            ScrollSpyMessageHandler(owner: self),
            name: "scrollSpy"
        )
        webView.configuration.userContentController.add(
            CopyCodeMessageHandler(),
            name: "copyCode"
        )

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservingTheme()
        startObservingFont()
    }

    // MARK: - Loading

    /// Load and render a markdown file.
    /// Very large markdown files (≥10MB) are truncated to prevent excessive memory use
    /// from parsing and rendering the full document.
    func loadMarkdownFile(at url: URL) {
        _ = self.view // Ensure webView is in the hierarchy
        currentFileURL = url

        let fileSize = url.fileSize

        // For very large markdown files, load only the first portion
        if fileSize >= FileSizeThreshold.markdownTruncation {
            let truncatedText = Self.readFirstLines(from: url, maxLines: 10_000)
            let sizeLabel = formattedFileSize(fileSize)
            let warningHTML = "<div style='background:rgba(255,180,0,0.15); padding:8px 12px; "
                + "border-radius:6px; margin-bottom:16px; font-size:12px; color:#b89500;'>"
                + "Large file (\(sizeLabel)) — showing first 10,000 lines. "
                + "Use Code Preview for the full file.</div>"
            let document = Document(parsing: truncatedText)
            let htmlBody = warningHTML + HTMLConverter.convert(document)
            let fullHTML = Self.wrapInHTMLPage(body: htmlBody)
            webView.loadHTMLString(fullHTML, baseURL: url.deletingLastPathComponent())
            return
        }

        guard let markdownString = try? String(contentsOf: url, encoding: .utf8) else {
            webView.loadHTMLString("<p>Unable to read file.</p>", baseURL: nil)
            return
        }

        let document = Document(parsing: markdownString)
        let htmlBody = HTMLConverter.convert(document)
        let fullHTML = Self.wrapInHTMLPage(body: htmlBody)
        webView.loadHTMLString(fullHTML, baseURL: url.deletingLastPathComponent())
    }

    /// Show a placeholder when no file is selected.
    func showPlaceholder(message: String = "Select a file to preview") {
        _ = self.view
        currentFileURL = nil
        let html = Self.wrapInHTMLPage(
            body: "<p style='color:#888; text-align:center; margin-top:40px;'>\(message)</p>"
        )
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Load and display an image file using base64 data URI to bypass WKWebView file restrictions.
    func loadImageFile(at url: URL) {
        _ = self.view
        currentFileURL = url

        guard let imageData = try? Data(contentsOf: url) else {
            showPlaceholder(message: "Unable to read image")
            return
        }

        // Determine MIME type from extension
        let ext = url.pathExtension.lowercased()
        let mime: String = switch ext {
        case "png":             "image/png"
        case "jpg", "jpeg":     "image/jpeg"
        case "gif":             "image/gif"
        case "webp":            "image/webp"
        case "svg":             "image/svg+xml"
        case "bmp":             "image/bmp"
        case "tiff", "tif":     "image/tiff"
        case "ico":             "image/x-icon"
        case "heic", "heif":    "image/heic"
        default:                "image/png"
        }

        let base64 = imageData.base64EncodedString()
        let html = Self.wrapInHTMLPage(
            body: "<div style='text-align:center; padding:16px;'>"
                + "<img src='data:\(mime);base64,\(base64)' style='max-width:100%; max-height:90vh; object-fit:contain;'>"
                + "<p style='color:#888; margin-top:8px;'>\(url.lastPathComponent)</p></div>"
        )
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Load and display a PDF file using the native WKWebView PDF renderer.
    func loadPDFFile(at url: URL) {
        _ = self.view
        currentFileURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Load and display an HTML file using native WKWebView rendering.
    /// Very large HTML files (≥10MB) show a size warning before loading.
    func loadHTMLFile(at url: URL) {
        _ = self.view
        currentFileURL = url

        let fileSize = url.fileSize
        if fileSize >= FileSizeThreshold.markdownTruncation {
            let sizeLabel = formattedFileSize(fileSize)
            let warningHTML = Self.wrapInHTMLPage(
                body: "<div style='text-align:center; margin-top:40px; color:#888;'>"
                    + "<p>Large HTML file (\(sizeLabel))</p>"
                    + "<p style='font-size:12px;'>Use Code Preview for better performance with large files.</p>"
                    + "</div>"
            )
            webView.loadHTMLString(warningHTML, baseURL: nil)
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Fallback for plain text files that don't route through CodePreviewViewController.
    func loadTextFile(at url: URL) {
        _ = self.view
        currentFileURL = url
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            showPlaceholder(message: "Unable to read file")
            return
        }
        let escaped = contents
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = Self.wrapInHTMLPage(body: "<pre><code>\(escaped)</code></pre>")
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    // MARK: - Outline Navigation

    /// Scrolls the rendered preview to the heading with the given anchor ID.
    func scrollToHeading(id: String) {
        let js = "document.getElementById('\(id)')?.scrollIntoView({behavior: 'smooth', block: 'start'});"
        webView.evaluateJavaScript(js)
    }

    // MARK: - Content Search

    /// Searches the rendered HTML for the given query and highlights all matches.
    /// Supports regex, case-sensitive, and whole-word toggle flags.
    /// Returns the total number of matches found, or -1 for invalid regex.
    func searchContent(
        _ query: String,
        isRegex: Bool = false,
        caseSensitive: Bool = false,
        wholeWord: Bool = false
    ) async -> Int {
        guard !query.isEmpty else {
            clearSearchHighlights()
            return 0
        }

        let escaped = Self.escapeJSString(query)
        let js = """
        (function() {
            document.querySelectorAll('mark.search-hl').forEach(function(m) {
                var p = m.parentNode;
                p.replaceChild(document.createTextNode(m.textContent), m);
                p.normalize();
            });
            var query = '\(escaped)';
            if (!query) return 0;
            var isRegex = \(isRegex ? "true" : "false");
            var caseSensitive = \(caseSensitive ? "true" : "false");
            var wholeWord = \(wholeWord ? "true" : "false");

            // Build a RegExp for all match modes
            var pattern;
            try {
                if (isRegex) {
                    pattern = wholeWord ? '\\\\b(?:' + query + ')\\\\b' : query;
                } else {
                    var esc = query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                    pattern = wholeWord ? '\\\\b' + esc + '\\\\b' : esc;
                }
                var flags = 'g' + (caseSensitive ? '' : 'i');
                var re = new RegExp(pattern, flags);
            } catch(e) {
                return -1;
            }

            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            for (var i = nodes.length - 1; i >= 0; i--) {
                var node = nodes[i];
                var text = node.textContent;
                var matches = [];
                var m;
                re.lastIndex = 0;
                while ((m = re.exec(text)) !== null) {
                    matches.push({ index: m.index, length: m[0].length });
                    if (m[0].length === 0) { re.lastIndex++; }
                }
                for (var j = matches.length - 1; j >= 0; j--) {
                    var match = matches[j];
                    var range = document.createRange();
                    range.setStart(node, match.index);
                    range.setEnd(node, match.index + match.length);
                    var mark = document.createElement('mark');
                    mark.className = 'search-hl';
                    range.surroundContents(mark);
                }
            }
            return document.querySelectorAll('mark.search-hl').length;
        })()
        """

        let result = try? await webView.evaluateJavaScript(js)
        return result as? Int ?? 0
    }

    /// Scrolls to and highlights the match at the given index.
    func navigateToSearchMatch(at index: Int) {
        let js = """
        (function() {
            var marks = document.querySelectorAll('mark.search-hl');
            marks.forEach(function(m) { m.classList.remove('search-hl-current'); });
            var idx = \(index);
            if (idx >= 0 && idx < marks.length) {
                marks[idx].classList.add('search-hl-current');
                marks[idx].scrollIntoView({behavior: 'smooth', block: 'center'});
            }
        })()
        """
        webView.evaluateJavaScript(js)
    }

    /// Removes all search highlights from the rendered HTML.
    func clearSearchHighlights() {
        let js = """
        document.querySelectorAll('mark.search-hl').forEach(function(m) {
            var p = m.parentNode;
            p.replaceChild(document.createTextNode(m.textContent), m);
            p.normalize();
        });
        """
        webView.evaluateJavaScript(js)
    }

    /// Escapes a string for safe embedding in a JavaScript string literal.
    private static func escapeJSString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - Theme Observation

    /// Starts observing theme changes to re-render the current content.
    private func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reloadCurrentContent()
                self?.startObservingTheme()
            }
        }
    }

    /// Watches FontManager for changes and re-renders content with the new code font.
    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reloadCurrentContent()
                self?.startObservingFont()
            }
        }
    }

    /// Re-renders whatever content is currently displayed using the new theme.
    private func reloadCurrentContent() {
        guard let url = currentFileURL else {
            showPlaceholder()
            return
        }
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            loadMarkdownFile(at: url)
        } else if let utType = UTType(filenameExtension: ext), utType.conforms(to: .pdf) {
            loadPDFFile(at: url)
        } else if let utType = UTType(filenameExtension: ext), utType.conforms(to: .image) {
            loadImageFile(at: url)
        } else {
            loadTextFile(at: url)
        }
    }

    // MARK: - Large File Helpers

    /// Reads the first N lines from a file without loading the entire contents.
    /// Uses line-by-line reading to cap memory usage for very large files.
    private static func readFirstLines(from url: URL, maxLines: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        var lines: [String] = []
        lines.reserveCapacity(min(maxLines, 1000))

        // Read in 64KB chunks and split into lines
        let chunkSize = 65_536
        var remainder = ""

        while lines.count < maxLines {
            guard let chunk = try? handle.read(upToCount: chunkSize),
                  !chunk.isEmpty else { break }

            let text = remainder + String(decoding: chunk, as: UTF8.self)
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)

            // All parts except the last are complete lines
            for i in 0..<(parts.count - 1) {
                lines.append(String(parts[i]))
                if lines.count >= maxLines { break }
            }

            // Last part may be a partial line — carry over
            remainder = String(parts.last ?? "")
        }

        // Include any trailing partial line
        if lines.count < maxLines && !remainder.isEmpty {
            lines.append(remainder)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - HTML Template

    /// Wraps HTML body content in a full page with theme-driven styling.
    /// Colors are derived from the active theme rather than hardcoded.
    /// Includes scroll spy JavaScript that reports visible headings via WKScriptMessageHandler.
    private static func wrapInHTMLPage(body: String) -> String {
        let theme = ThemeManager.shared.activeTheme
        let bg = theme.hexString(for: \.background)
        let fg = theme.hexString(for: \.foreground)
        let accent = theme.paletteColor(at: 4).hexString // Blue
        // Code block background — slightly darker than body for contrast
        let codeBg = (theme.backgroundColor.blended(withFraction: 0.08, of: .black)
            ?? theme.backgroundColor).hexString
        let border = theme.chromeBorder.hexString

        // Syntax coloring classes — mapped to ANSI palette for theme consistency
        // Heading colors — use accent (blue) for h1, palette colors for h2–h4
        let h1Color = accent                                       // blue
        let h2Color = theme.paletteColor(at: 6).hexString          // cyan
        let h3Color = theme.paletteColor(at: 5).hexString          // magenta
        let h4Color = theme.paletteColor(at: 3).hexString          // yellow

        let synComment = theme.chromeTextSecondary.hexString     // dimmed text
        let synString  = theme.paletteColor(at: 2).hexString     // green
        let synKeyword = theme.paletteColor(at: 5).hexString     // magenta
        let synNumber  = theme.paletteColor(at: 6).hexString     // cyan
        let synKey     = theme.paletteColor(at: 3).hexString     // yellow

        // Get CSS font-face rule + family name from FontManager.
        // Bundled fonts are embedded as base64 data URIs since WKWebView
        // runs in a separate process and can't see process-scoped fonts.
        let (fontFaceRule, fontFamily) = FontManager.shared.cssFontFace

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            \(fontFaceRule)
            body {
                font-family: "\(fontFamily)", Menlo, Consolas, monospace;
                font-size: 14px;
                line-height: 1.6;
                color: #\(fg);
                background: #\(bg);
                padding: 16px 24px;
                max-width: 800px;
                margin: 0 auto;
            }
            h1, h2, h3, h4, h5, h6 { margin-top: 1.2em; margin-bottom: 0.4em; }
            h1 { font-size: 1.8em; color: #\(h1Color); border-bottom: 1px solid #\(border); padding-bottom: 0.3em; }
            h2 { font-size: 1.4em; color: #\(h2Color); border-bottom: 1px solid #\(border); padding-bottom: 0.2em; }
            h3 { font-size: 1.2em; color: #\(h3Color); }
            h4 { font-size: 1.1em; color: #\(h4Color); }
            h5, h6 { font-size: 1em; color: #\(h4Color); opacity: 0.8; }
            code {
                font-family: "\(fontFamily)", Menlo, Consolas, monospace;
                font-size: 0.9em;
                background: #\(codeBg);
                padding: 2px 6px;
                border-radius: 4px;
            }
            pre {
                background: #\(codeBg);
                padding: 12px 16px;
                border-radius: 8px;
                overflow-x: auto;
                position: relative;
            }
            pre code { background: none; padding: 0; }
            /* Copy button — top-right of code blocks, visible on hover */
            pre .copy-btn {
                position: absolute;
                top: 6px;
                right: 6px;
                background: #\(bg);
                border: 1px solid #\(border);
                border-radius: 4px;
                color: #\(fg);
                font-size: 11px;
                padding: 2px 8px;
                cursor: pointer;
                opacity: 0;
                transition: opacity 0.15s;
            }
            pre:hover .copy-btn { opacity: 0.7; }
            pre .copy-btn:hover { opacity: 1; }
            blockquote {
                margin: 0;
                padding: 4px 16px;
                border-left: 4px solid #\(border);
                color: #\(fg);
                opacity: 0.7;
            }
            table { border-collapse: collapse; width: 100%; margin: 1em 0; }
            table th, table td {
                border: 1px solid #\(border);
                padding: 8px 12px;
                text-align: left;
            }
            table th { background: #\(codeBg); font-weight: 600; }
            img { max-width: 100%; border-radius: 4px; }
            hr { border: none; border-top: 1px solid #\(border); margin: 1.5em 0; }
            a { color: #\(accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            ul, ol { padding-left: 1.5em; }
            li { margin: 0.2em 0; }
            /* Syntax coloring — theme-derived from ANSI palette */
            .syn-comment { color: #\(synComment); font-style: italic; }
            .syn-string  { color: #\(synString); }
            .syn-keyword { color: #\(synKeyword); }
            .syn-number  { color: #\(synNumber); }
            .syn-key     { color: #\(synKey); }
            /* Content search highlights */
            mark.search-hl { background: rgba(255, 200, 0, 0.3); color: inherit; border-radius: 2px; padding: 0 1px; }
            mark.search-hl-current { background: rgba(255, 150, 0, 0.6); }
        </style>
        </head>
        <body>\(body)</body>
        <script>
        // Scroll spy: observe heading visibility and post the topmost visible heading ID.
        (function() {
            const headings = document.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');
            if (!headings.length || !window.webkit?.messageHandlers?.scrollSpy) return;

            let lastReported = '';
            const observer = new IntersectionObserver(entries => {
                // Find the first visible heading closest to the top of the viewport
                let topId = '';
                let topY = Infinity;
                for (const h of headings) {
                    const rect = h.getBoundingClientRect();
                    // Consider headings that are above or near the viewport top
                    if (rect.top <= 60 && rect.top > -rect.height) {
                        if (rect.top > (topY === Infinity ? -Infinity : topY) || topId === '') {
                            topId = h.id;
                            topY = rect.top;
                        }
                    }
                }
                // Fallback: if nothing is above viewport, use first heading in viewport
                if (!topId) {
                    for (const h of headings) {
                        const rect = h.getBoundingClientRect();
                        if (rect.top >= 0 && rect.top < window.innerHeight) {
                            topId = h.id;
                            break;
                        }
                    }
                }
                if (topId && topId !== lastReported) {
                    lastReported = topId;
                    window.webkit.messageHandlers.scrollSpy.postMessage(topId);
                }
            }, { threshold: [0, 0.5, 1] });

            headings.forEach(h => observer.observe(h));

            // Also fire on scroll for more responsive updates
            document.addEventListener('scroll', () => {
                let topId = '';
                for (const h of headings) {
                    const rect = h.getBoundingClientRect();
                    if (rect.top <= 60) {
                        topId = h.id;
                    }
                }
                if (!topId && headings.length) topId = headings[0].id;
                if (topId && topId !== lastReported) {
                    lastReported = topId;
                    window.webkit.messageHandlers.scrollSpy.postMessage(topId);
                }
            }, { passive: true });
        })();

        // Copy button: inject a copy button into every <pre> code block.
        // Clicks send the raw code text to Swift via WKScriptMessageHandler
        // since WKWebView sandboxes direct clipboard access.
        (function() {
            if (!window.webkit?.messageHandlers?.copyCode) return;
            document.querySelectorAll('pre').forEach(pre => {
                const btn = document.createElement('button');
                btn.className = 'copy-btn';
                btn.textContent = 'Copy';
                btn.addEventListener('click', () => {
                    const code = pre.querySelector('code');
                    const text = (code || pre).innerText;
                    window.webkit.messageHandlers.copyCode.postMessage(text);
                    btn.textContent = 'Copied!';
                    setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
                });
                pre.appendChild(btn);
            });
        })();
        </script>
        </html>
        """
    }
}

// MARK: - Scroll Spy Message Handler

/// Wraps the WKScriptMessageHandler in a separate class to avoid retain cycles.
/// NSObject subclass required by WKScriptMessageHandler protocol.
private class ScrollSpyMessageHandler: NSObject, WKScriptMessageHandler {

    private weak var owner: MarkdownPreviewViewController?

    init(owner: MarkdownPreviewViewController) {
        self.owner = owner
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let headingID = message.body as? String else { return }
        Task { @MainActor [weak owner] in
            owner?.onVisibleHeadingChanged?(headingID)
        }
    }
}

// MARK: - Copy Code Message Handler

/// Handles copy-to-clipboard requests from the code block copy button.
/// WKWebView sandboxes direct clipboard access, so JavaScript posts the
/// code text here and we write it to the system pasteboard via AppKit.
private class CopyCodeMessageHandler: NSObject, WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let text = message.body as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - WKNavigationDelegate (Link Interception)

extension MarkdownPreviewViewController: WKNavigationDelegate {

    /// Intercepts link clicks to route local file/folder URLs to the file explorer
    /// instead of navigating the web view.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow initial page loads (loadHTMLString, loadFileURL)
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Only intercept local file:// URLs
        guard url.isFileURL else {
            // Open external URLs in the default browser
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // Route to file explorer based on whether the target is a directory or file
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            onFolderLinkClicked?(url)
        } else {
            onFileLinkClicked?(url)
        }

        decisionHandler(.cancel)
    }
}

// MARK: - HTML Converter

/// Converts a swift-markdown Document to an HTML string.
/// Adds `id` attributes to headings for anchor-based scrolling from the outline.
/// IDs use sequential "heading-{N}" format matching the outline's heading indices.
private enum HTMLConverter {

    /// Tracks heading offsets for generating stable anchor IDs.
    private final class RenderContext {
        var headingCounter = 0
    }

    static func convert(_ document: Document) -> String {
        let ctx = RenderContext()
        var html = ""
        for child in document.children {
            html += renderMarkup(child, context: ctx)
        }
        return html
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func renderMarkup(_ markup: any Markup, context: RenderContext) -> String {
        switch markup {
        case let heading as Heading:
            let level = heading.level
            let content = heading.children.map { renderMarkup($0, context: context) }.joined()
            // Sequential anchor ID for outline scroll-to-heading navigation.
            // Matches the heading's index in MarkdownHeadingParser output.
            let anchorID = "heading-\(context.headingCounter)"
            context.headingCounter += 1
            return "<h\(level) id=\"\(anchorID)\">\(content)</h\(level)>\n"

        case let paragraph as Paragraph:
            let content = paragraph.children.map { renderMarkup($0, context: context) }.joined()
            return "<p>\(content)</p>\n"

        case let text as Text:
            return escapeHTML(text.string)

        case let strong as Strong:
            let content = strong.children.map { renderMarkup($0, context: context) }.joined()
            return "<strong>\(content)</strong>"

        case let emphasis as Emphasis:
            let content = emphasis.children.map { renderMarkup($0, context: context) }.joined()
            return "<em>\(content)</em>"

        case let code as InlineCode:
            return "<code>\(escapeHTML(code.code))</code>"

        case let codeBlock as CodeBlock:
            let lang = codeBlock.language ?? ""
            let langAttr = lang.isEmpty ? "" : " class=\"language-\(lang)\""
            // Apply syntax highlighting when a recognized language tag is present.
            // Falls back to plain escaped text for untagged or unrecognized languages.
            let highlighted: String
            if !lang.isEmpty {
                let langID = CodeSyntaxHighlighter.languageFromTag(lang)
                let patterns = CodeSyntaxHighlighter.patterns(for: langID)
                if !patterns.isEmpty {
                    highlighted = CodeSyntaxHighlighter.highlightToHTML(code: codeBlock.code, language: lang)
                } else {
                    highlighted = escapeHTML(codeBlock.code)
                }
            } else {
                highlighted = escapeHTML(codeBlock.code)
            }
            return "<pre><code\(langAttr)>\(highlighted)</code></pre>\n"

        case let link as Link:
            let content = link.children.map { renderMarkup($0, context: context) }.joined()
            let href = link.destination ?? ""
            return "<a href=\"\(href)\">\(content)</a>"

        case let image as Image:
            let alt = image.children.map { renderMarkup($0, context: context) }.joined()
            let src = image.source ?? ""
            return "<img src=\"\(src)\" alt=\"\(alt)\">"

        case let list as UnorderedList:
            let items = list.children.map { renderMarkup($0, context: context) }.joined()
            return "<ul>\(items)</ul>\n"

        case let list as OrderedList:
            let items = list.children.map { renderMarkup($0, context: context) }.joined()
            return "<ol>\(items)</ol>\n"

        case let item as ListItem:
            let content = item.children.map { renderMarkup($0, context: context) }.joined()
            return "<li>\(content)</li>\n"

        case let quote as BlockQuote:
            let content = quote.children.map { renderMarkup($0, context: context) }.joined()
            return "<blockquote>\(content)</blockquote>\n"

        case is ThematicBreak:
            return "<hr>\n"

        case let softBreak as SoftBreak:
            _ = softBreak
            return "\n"

        case let lineBreak as LineBreak:
            _ = lineBreak
            return "<br>\n"

        case let table as Markdown.Table:
            return renderTable(table, context: context)

        case let html as InlineHTML:
            return html.rawHTML

        case let html as HTMLBlock:
            return html.rawHTML

        default:
            // Fallback: render children
            return markup.children.map { renderMarkup($0, context: context) }.joined()
        }
    }

    private static func renderTable(_ table: Markdown.Table, context: RenderContext) -> String {
        var html = "<table>\n"

        // Header
        html += "<thead><tr>"
        for cell in table.head.cells {
            let content = cell.children.map { renderMarkup($0, context: context) }.joined()
            html += "<th>\(content)</th>"
        }
        html += "</tr></thead>\n"

        // Body
        html += "<tbody>"
        for row in table.body.rows {
            html += "<tr>"
            for cell in row.cells {
                let content = cell.children.map { renderMarkup($0, context: context) }.joined()
                html += "<td>\(content)</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody></table>\n"

        return html
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
