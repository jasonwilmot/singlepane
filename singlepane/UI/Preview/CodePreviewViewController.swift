// CodePreviewViewController.swift
// Read-only NSTextView with syntax highlighting for source code and developer files.
// Uses CodeSyntaxHighlighter for coloring and pretty-prints structured formats (JSON, PLIST).
// Styled identically to EditorViewController but non-editable.
//
// Large file support (≥1MB):
//   Files are memory-mapped via LargeFileReader. Only a window of lines around the
//   scroll position is loaded into the NSTextView. The window updates on scroll via
//   a simulated document height using a spacer view.

import AppKit

@MainActor
final class CodePreviewViewController: NSViewController {

    // MARK: - Properties

    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var lineNumberGutter: LineNumberGutterView!
    private var syntaxHighlighter: CodeSyntaxHighlighter?

    /// Active mmap reader for large files. Nil when the file is loaded normally.
    private(set) var largeFileReader: LargeFileReader?

    /// Whether the current file is loaded via mmap (visible-window mode).
    var isMmapMode: Bool { largeFileReader != nil }

    /// The line range currently loaded into the text view (mmap mode only).
    private var currentWindowRange: Range<Int> = 0..<0

    /// Number of lines to load into the visible window (with buffer above/below).
    private static let windowSize = 500

    /// Extra buffer lines above and below the visible area to reduce flicker on scroll.
    private static let windowBuffer = 100

    /// Max bytes to load into the text view in any single window update.
    /// Prevents NSLayoutManager from choking on minified files with mega-lines.
    private static let maxBytesPerWindow = 131_072 // 128 KB

    /// Max characters per line before truncation. Lines longer than this are clipped
    /// to avoid NSLayoutManager layout explosion (word wrap on 5000+ char lines).
    private static let maxCharsPerLine = 2_000

    /// True when the file has extremely long lines (minified/bundled).
    /// Triggers per-line truncation and disables syntax highlighting.
    private var isLongLineFile = false

    /// Estimated line height for scroll position calculations.
    private var estimatedLineHeight: CGFloat = 14

    /// Spacer view used to simulate full document height in mmap mode.
    private var spacerView: NSView?

    /// Debounce timer for scroll-triggered window updates.
    private var scrollDebounceTimer: Timer?

    /// In-flight async load task — cancelled when a new file is loaded.
    private var loadTask: Task<Void, Never>?

    // MARK: - Public Accessors

    /// The preview text view, for external search operations.
    var previewTextView: NSTextView? { textView }

    /// The preview scroll view, for external scroll operations.
    var previewScrollView: NSScrollView? { scrollView }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))

        // Line number gutter (positioned to the left of the scroll view)
        lineNumberGutter = LineNumberGutterView()
        lineNumberGutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lineNumberGutter)

        scrollView = NSScrollView(frame: container.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentSize = scrollView.contentSize
        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = FontManager.shared.activeFont
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 8, height: 16)
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // Wire gutter to text view
        lineNumberGutter.textView = textView

        NSLayoutConstraint.activate([
            lineNumberGutter.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            lineNumberGutter.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            lineNumberGutter.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            lineNumberGutter.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservingFont()
        startObservingTheme()

        // Sync gutter with text scroll position
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    // MARK: - Loading

    /// Loads a source file with syntax highlighting and pretty-printing.
    /// Files ≥1MB are memory-mapped and rendered with visible-window scrolling.
    /// Cancels any in-flight load from a previous file selection.
    func loadFile(at url: URL) {
        _ = self.view

        // Cancel any in-flight async load
        loadTask?.cancel()
        loadTask = nil

        let fileSize = url.fileSize
        let ext = url.pathExtension.lowercased()

        if fileSize >= FileSizeThreshold.normalLoad {
            loadLargeFile(at: url, ext: ext)
        } else {
            loadNormalFile(at: url, ext: ext)
        }
    }

    // MARK: - Normal Loading (< 1MB)

    private func loadNormalFile(at url: URL, ext: String) {
        // Clear mmap state from any previous large file
        exitMmapMode()

        guard var contents = try? String(contentsOf: url, encoding: .utf8) else {
            textView.string = ""
            return
        }

        // Pretty-print structured formats (only for small files)
        contents = Self.prettyPrint(contents, fileExtension: ext)

        // Install highlighter for this language
        let lang = CodeSyntaxHighlighter.language(for: ext)
        let hl = CodeSyntaxHighlighter(textView: textView)
        hl.language = lang
        syntaxHighlighter = hl

        textView.string = contents
        applyTheme()
        syntaxHighlighter?.highlightAll()
        refreshGutter()
    }

    // MARK: - Large File Loading (≥ 1MB, mmap)

    private func loadLargeFile(at url: URL, ext: String) {
        // Show immediate feedback while the file loads in the background
        textView.string = ""

        loadTask = Task { [weak self] in
            guard let self else { return }

            // Build the reader off the main thread — scanning 6MB+ for newlines
            // on the main thread causes the system spinner.
            let reader: LargeFileReader? = await Task.detached(priority: .userInitiated) {
                try? LargeFileReader(url: url)
            }.value

            guard !Task.isCancelled, let reader else {
                self.textView.string = "Unable to memory-map file."
                return
            }

            // Store reader — this signals mmap mode to the rest of the system
            self.largeFileReader = reader

            let totalLines = await reader.lineCount
            let maxLineLen = await reader.maxLineLength
            guard !Task.isCancelled else { return }

            // Detect minified/bundled files: few lines but very long lines.
            // NSLayoutManager chokes on lines >5000 chars with word wrap enabled.
            self.isLongLineFile = maxLineLen > Self.maxCharsPerLine

            if self.isLongLineFile {
                // Disable word wrap — layout of 5000+ char wrapped lines is the #1 perf killer
                self.textView.textContainer?.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                self.textView.textContainer?.widthTracksTextView = false
                self.textView.isHorizontallyResizable = true
                self.scrollView.hasHorizontalScroller = true
            }

            self.lineNumberGutter.overrideTotalLineCount = totalLines
            self.lineNumberGutter.lineNumberOffset = 0

            // Calculate estimated line height from the current font
            self.estimatedLineHeight = FontManager.shared.activeFont.pointSize * 1.4

            // Install syntax highlighter for visible-window re-highlighting
            // Skip for long-line files — regex over minified code is both slow and useless
            if !self.isLongLineFile {
                let lang = CodeSyntaxHighlighter.language(for: ext)
                let hl = CodeSyntaxHighlighter(textView: self.textView)
                hl.language = lang
                self.syntaxHighlighter = hl
            } else {
                self.syntaxHighlighter = nil
            }

            // Set up the spacer view to simulate full document height
            self.setupMmapScrolling(totalLines: totalLines)

            guard !Task.isCancelled else { return }

            // Load the initial window (first N lines)
            await self.loadWindow(startLine: 0)

            guard !Task.isCancelled else { return }
            self.applyTheme()
            self.refreshGutter()
        }
    }

    /// Configures the scroll view to simulate the full document height using a spacer.
    /// The text view sits at the top; a transparent spacer below it creates the total height.
    private func setupMmapScrolling(totalLines: Int) {
        // Remove previous spacer if any
        spacerView?.removeFromSuperview()

        // Create a container that holds the text view + spacer
        let totalHeight = CGFloat(totalLines) * estimatedLineHeight
        let containerView = NSView(frame: NSRect(
            x: 0, y: 0,
            width: scrollView.contentSize.width,
            height: totalHeight
        ))
        containerView.autoresizingMask = [.width]

        // Text view at the top of the container, sized to fit its content
        textView.frame = NSRect(
            x: 0, y: 0,
            width: containerView.bounds.width,
            height: totalHeight
        )
        textView.autoresizingMask = [.width]
        containerView.addSubview(textView)

        scrollView.documentView = containerView
        spacerView = containerView

        // Re-wire gutter to the text view (documentView changed)
        lineNumberGutter.textView = textView
    }

    /// Loads a window of lines centered around the given start line into the text view.
    /// For long-line files (minified/bundled), truncates each line to `maxCharsPerLine`
    /// to prevent NSLayoutManager from spending minutes computing line fragment layouts.
    private func loadWindow(startLine: Int) async {
        guard let reader = largeFileReader else { return }

        let totalLines = await reader.lineCount
        let clampedStart = max(0, startLine)

        // For long-line files, limit the number of lines further to stay within byte budget
        let effectiveWindowSize: Int
        if isLongLineFile {
            // Estimate: each truncated line ≤ maxCharsPerLine, so we can fit more lines
            // but cap at the standard window size
            let maxLines = max(50, Self.maxBytesPerWindow / Self.maxCharsPerLine)
            effectiveWindowSize = min(maxLines, Self.windowSize)
        } else {
            effectiveWindowSize = Self.windowSize
        }

        let windowEnd = min(clampedStart + effectiveWindowSize, totalLines)
        let windowRange = clampedStart..<windowEnd

        // Skip reload if we're already showing this range
        guard windowRange != currentWindowRange else { return }
        currentWindowRange = windowRange

        // Read the window's text from the memory-mapped file
        var windowText = await reader.readLines(windowRange)

        // For long-line files, truncate each line to prevent layout manager choking
        if isLongLineFile {
            windowText = Self.truncateLongLines(windowText, maxChars: Self.maxCharsPerLine)
        }

        // Update the text view content
        textView.string = windowText

        // Position text view within the spacer so it aligns with the scroll position
        let yOffset = CGFloat(clampedStart) * estimatedLineHeight
        textView.frame.origin.y = yOffset
        textView.frame.size.height = CGFloat(windowEnd - clampedStart) * estimatedLineHeight

        // Update gutter offset so line numbers are correct
        lineNumberGutter.lineNumberOffset = clampedStart

        // Re-highlight the visible window (skipped for long-line files)
        syntaxHighlighter?.highlightAll()
        lineNumberGutter.needsDisplay = true
    }

    /// Truncates each line in the text to the given max character count.
    /// Appends " …" to truncated lines so the user knows content was clipped.
    private static func truncateLongLines(_ text: String, maxChars: Int) -> String {
        var result = ""
        result.reserveCapacity(min(text.count, maxChars * 500))

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            // Find end of this line
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let lineLength = text.distance(from: lineStart, to: lineEnd)

            if lineLength > maxChars {
                // Truncate: take first maxChars characters + indicator
                let truncEnd = text.index(lineStart, offsetBy: maxChars)
                result.append(contentsOf: text[lineStart..<truncEnd])
                result.append(" \u{2026}") // " …"
            } else {
                result.append(contentsOf: text[lineStart..<lineEnd])
            }

            // Include the newline if present
            if lineEnd < text.endIndex {
                result.append("\n")
                lineStart = text.index(after: lineEnd)
            } else {
                lineStart = text.endIndex
            }
        }

        return result
    }

    /// Exits mmap mode — restores normal text view as the scroll view's document.
    private func exitMmapMode() {
        largeFileReader = nil
        currentWindowRange = 0..<0
        lineNumberGutter.overrideTotalLineCount = nil
        lineNumberGutter.lineNumberOffset = 0

        // Restore word wrap if it was disabled for a long-line file
        if isLongLineFile {
            let contentWidth = scrollView.contentSize.width
            textView.textContainer?.containerSize = NSSize(
                width: contentWidth, height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
            isLongLineFile = false
        }

        if spacerView != nil {
            // Restore text view as direct document view
            spacerView?.removeFromSuperview()
            spacerView = nil
            textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
            textView.autoresizingMask = [.width]
            scrollView.documentView = textView
            lineNumberGutter.textView = textView
        }
    }

    /// Scrolls the mmap view to make the given line visible.
    func scrollToLine(_ line: Int) {
        guard isMmapMode else { return }
        let yOffset = CGFloat(line) * estimatedLineHeight
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: yOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // Trigger a window update for the new position
        Task { await updateWindowForScrollPosition() }
    }

    // MARK: - Pretty Printing

    private static func prettyPrint(_ contents: String, fileExtension ext: String) -> String {
        switch ext {
        case "json", "geojson", "har":
            guard let data = contents.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(
                      withJSONObject: obj,
                      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                  ),
                  let str = String(data: pretty, encoding: .utf8)
            else { return contents }
            return str
        case "plist":
            guard let data = contents.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ),
                  let pretty = try? PropertyListSerialization.data(
                      fromPropertyList: plist, format: .xml, options: 0
                  ),
                  let str = String(data: pretty, encoding: .utf8)
            else { return contents }
            return str
        default:
            return contents
        }
    }

    // MARK: - Theme

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        textView.backgroundColor = theme.backgroundColor
        textView.textColor = theme.foregroundColor
        textView.insertionPointColor = theme.foregroundColor
        scrollView.backgroundColor = theme.backgroundColor
        view.layer?.backgroundColor = theme.backgroundColor.cgColor
    }

    private func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.syntaxHighlighter?.highlightAll()
                self?.refreshGutter()
                self?.startObservingTheme()
            }
        }
    }

    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.textView.font = FontManager.shared.activeFont
                self?.estimatedLineHeight = FontManager.shared.activeFont.pointSize * 1.4
                self?.syntaxHighlighter?.highlightAll()
                self?.refreshGutter()
                self?.startObservingFont()
            }
        }
    }

    // MARK: - Gutter

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        lineNumberGutter.needsDisplay = true

        // In mmap mode, update the visible window on scroll (debounced)
        if isMmapMode {
            scrollDebounceTimer?.invalidate()
            scrollDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.05, repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateWindowForScrollPosition()
                }
            }
        }
    }

    /// Calculates which line the scroll view is showing and updates the mmap window.
    private func updateWindowForScrollPosition() async {
        guard isMmapMode else { return }
        let scrollY = scrollView.contentView.bounds.origin.y
        let currentLine = max(0, Int(scrollY / estimatedLineHeight))
        let windowStart = max(0, currentLine - Self.windowBuffer)
        await loadWindow(startLine: windowStart)
    }

    private func refreshGutter() {
        lineNumberGutter.updateWidth()
        lineNumberGutter.needsDisplay = true
    }
}
