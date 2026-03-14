// EditorViewController.swift
// NSTextView-based text editor with two modes:
//   • Markdown: iA Writer-style editing — no line numbers, paragraph indentation
//     places `#` markers in the left margin, auto-continues lists on Return.
//   • Code: standard line-numbered editor for all other file types.
//
// The toolbar (Save/Edit buttons) is owned by PreviewContainerViewController.
// This VC exposes `saveFile()` and `scrollToRange()` for parent control.

import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {

    // MARK: - Properties

    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var lineNumberGutter: LineNumberGutterView!
    private var currentFileURL: URL?
    private var syntaxHighlighter: SyntaxHighlighting?

    /// Whether the current file is markdown (controls gutter visibility and editing behavior).
    private var isMarkdownMode = false

    /// The detected syntax language for the current file (e.g. "html", "swift", "json").
    /// Used by bracket matching to enable angle brackets for HTML/XML.
    private(set) var currentLanguage = "text"

    /// The detected file encoding, used for save and displayed in the status bar.
    private(set) var fileEncoding: String.Encoding = .utf8

    /// The detected line ending type, displayed in the status bar.
    private(set) var lineEndings: LineEnding = .lf

    /// The detected indentation style, displayed in the status bar.
    private(set) var indentStyle: IndentStyle = .spaces(4)

    /// Whether soft word wrap is enabled. On by default.
    private(set) var wordWrapEnabled: Bool = true

    /// Constraint pinning the scroll view's leading edge to the gutter's trailing edge.
    /// Swapped with `scrollViewLeadingToContainer` when the gutter is hidden.
    private var scrollViewLeadingToGutter: NSLayoutConstraint!

    /// Constraint pinning the scroll view's leading edge directly to the container.
    /// Active when the gutter is hidden (markdown mode).
    private var scrollViewLeadingToContainer: NSLayoutConstraint!

    /// Called when the editor text changes (for live outline updates).
    var onTextChanged: ((String) -> Void)?

    /// Called when the cursor position or selection changes.
    /// Parameters: (line, column, selectionLength).
    var onSelectionChanged: ((Int, Int, Int) -> Void)?

    /// Called when encoding, line endings, or indent style change via status bar actions.
    var onFileMetadataChanged: (() -> Void)?

    /// Dismissible warning banner shown for large files.
    private var warningBanner: NSView?

    /// Character ranges currently highlighted by bracket matching.
    /// Tracked so they can be cleared efficiently on the next selection change
    /// without wiping search highlights across the entire document.
    private var bracketHighlightRanges: [NSRange] = []

    // MARK: - Public Accessors

    /// The editor's current text content.
    var text: String { textView?.string ?? "" }

    /// The editor's scroll view, for external scroll position observation.
    var editorScrollView: NSScrollView? { scrollView }

    /// The editor's text view, for external search operations.
    var editorTextView: NSTextView? { textView }

    /// Re-applies syntax highlighting to the full document.
    /// Called after replace operations to restore correct coloring.
    func rehighlight() {
        syntaxHighlighter?.highlightAll()
    }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))

        // Line number gutter (positioned to the left of the scroll view)
        lineNumberGutter = LineNumberGutterView()
        lineNumberGutter.highlightsCurrentLine = true
        lineNumberGutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lineNumberGutter)

        // Scroll view — NSTextView needs a properly sized container
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Create text view sized to the scroll view's content area
        let contentSize = scrollView.contentSize
        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = true
        textView.isRichText = true
        textView.font = FontManager.shared.activeFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 16)
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // Wire gutter to text view
        lineNumberGutter.textView = textView

        // Store swappable leading constraints for gutter show/hide
        scrollViewLeadingToGutter = scrollView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor)
        scrollViewLeadingToContainer = scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            lineNumberGutter.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            lineNumberGutter.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            lineNumberGutter.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            lineNumberGutter.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollViewLeadingToGutter,
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

        // Refresh gutter on selection change (current line highlight) and text edits
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    // MARK: - File Operations

    /// Load a file into the editor. Selects the appropriate syntax highlighter
    /// based on file extension and pretty-prints structured formats.
    /// For markdown files, hides the line number gutter and enables iA Writer-style editing.
    /// Files ≥1MB show a dismissible warning banner; pretty-printing is skipped for large files.
    func loadFile(at url: URL) {
        currentFileURL = url

        // Force view to load if it hasn't yet — textView is created in loadView()
        _ = self.view

        // Dismiss any previous warning banner
        dismissWarningBanner()

        let fileSize = url.fileSize

        // Detect encoding from raw bytes before reading as string
        fileEncoding = FileEncodingDetector.detectEncoding(at: url)

        var contents: String
        if let decoded = try? String(contentsOf: url, encoding: fileEncoding) {
            contents = decoded
        } else if fileEncoding != .utf8, let fallback = try? String(contentsOf: url, encoding: .utf8) {
            // Fall back to UTF-8 if detected encoding fails
            fileEncoding = .utf8
            contents = fallback
        } else {
            textView.string = ""
            return
        }

        // Detect line endings and indent style from file contents
        lineEndings = FileEncodingDetector.detectLineEndings(in: contents)
        indentStyle = FileEncodingDetector.detectIndentStyle(in: contents)

        let ext = url.pathExtension.lowercased()
        let lang = ext.isEmpty
            ? CodeSyntaxHighlighter.language(forFilename: url.lastPathComponent)
            : CodeSyntaxHighlighter.language(for: ext)
        currentLanguage = lang
        isMarkdownMode = (lang == "markdown")

        // Toggle gutter visibility: hidden for markdown, visible for code
        configureGutterVisibility()

        // Pretty-print structured formats — skip for large files to avoid memory spike
        if fileSize < FileSizeThreshold.normalLoad {
            contents = Self.prettyPrint(contents, fileExtension: ext)
        }

        // Detect long-line files (minified/bundled) and disable word wrap + highlighting.
        // NSLayoutManager chokes on lines >2000 chars with word wrap, and regex highlighting
        // on minified code is both slow and useless.
        let maxLineLen = Self.maxLineLength(in: contents)
        let isLongLineFile = maxLineLen > 2_000

        if isLongLineFile && wordWrapEnabled {
            wordWrapEnabled = false
            applyWordWrapSetting()
        }

        // Install the right highlighter for this file type.
        // Skip highlighting entirely for long-line files.
        // Enable incremental mode for large files to avoid full-text regex on every keystroke.
        if isLongLineFile {
            syntaxHighlighter = nil
        } else {
            installHighlighter(for: ext, incrementalMode: fileSize >= FileSizeThreshold.normalLoad)
        }

        // Wire delegate — always set for text change tracking;
        // markdown-specific editing behaviors are guarded by isMarkdownMode
        textView.delegate = self

        // Re-register text change observer — removing and re-adding the editor view
        // to the hierarchy can break notification delivery
        NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextChange),
            name: NSText.didChangeNotification,
            object: textView
        )

        textView.string = contents
        applyTheme()
        syntaxHighlighter?.highlightAll()
        refreshGutter()

        // Notify the container so the status bar can update
        onFileMetadataChanged?()

        // Fire initial cursor position (line 1, col 1, no selection)
        onSelectionChanged?(1, 1, 0)

        // Show a warning for large or minified files
        if isLongLineFile {
            showWarningBanner(
                "Minified file (\(formattedFileSize(fileSize))) — syntax highlighting disabled"
            )
        } else if fileSize >= FileSizeThreshold.editorWarning {
            showWarningBanner(
                "Large file (\(formattedFileSize(fileSize))) — editing may be slow"
            )
        }
    }

    /// Writes the current editor content to disk using the detected (or overridden) encoding.
    /// Returns the file URL on success, nil on failure.
    @discardableResult
    func saveFile() -> URL? {
        guard let url = currentFileURL else { return nil }
        do {
            try textView.string.write(to: url, atomically: true, encoding: fileEncoding)
            return url
        } catch {
            NSLog("Failed to save file: \(error)")
            return nil
        }
    }

    /// Scrolls the editor to make the given character range visible
    /// and places the insertion point at the start of the range.
    func scrollToRange(_ range: NSRange) {
        textView?.scrollRangeToVisible(range)
        textView?.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    // MARK: - Gutter Visibility

    /// Shows line numbers for code files, hides them for markdown.
    /// Deactivates the old constraint before activating the new one to avoid conflicts.
    private func configureGutterVisibility() {
        lineNumberGutter.isHidden = isMarkdownMode

        if isMarkdownMode {
            scrollViewLeadingToGutter.isActive = false
            scrollViewLeadingToContainer.isActive = true
        } else {
            scrollViewLeadingToContainer.isActive = false
            scrollViewLeadingToGutter.isActive = true
        }
    }

    // MARK: - Highlighter Selection

    /// Installs the appropriate syntax highlighter for the given file extension.
    /// When `incrementalMode` is true, the highlighter only re-highlights around
    /// edited regions instead of the full text — used for large files.
    private func installHighlighter(for ext: String, incrementalMode: Bool = false) {
        let lang = CodeSyntaxHighlighter.language(for: ext)
        if lang == "markdown" {
            syntaxHighlighter = MarkdownSyntaxHighlighter(textView: textView)
        } else {
            let codeHL = CodeSyntaxHighlighter(textView: textView)
            codeHL.language = lang
            codeHL.incrementalMode = incrementalMode
            syntaxHighlighter = codeHL
        }
    }

    // MARK: - Pretty Printing

    /// Pretty-prints structured formats for easier reading/editing.
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
        default:
            return contents
        }
    }

    // MARK: - Long Line Detection

    /// Returns the length of the longest line in the string.
    /// Scans only the first 256KB for performance on very large files.
    private static func maxLineLength(in text: String) -> Int {
        let scanLimit = min(text.count, 262_144)
        let scanEnd = text.index(text.startIndex, offsetBy: scanLimit)
        let prefix = text[text.startIndex..<scanEnd]

        var maxLen = 0
        var currentLen = 0
        for char in prefix {
            if char == "\n" {
                maxLen = max(maxLen, currentLen)
                currentLen = 0
            } else {
                currentLen += 1
            }
        }
        return max(maxLen, currentLen)
    }

    // MARK: - Font Observation

    /// Watches FontManager for changes and re-applies font and highlighting.
    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.textView.font = FontManager.shared.activeFont
                self?.syntaxHighlighter?.highlightAll()
                self?.refreshGutter()
                self?.startObservingFont()
            }
        }
    }

    /// Watches ThemeManager for changes and re-applies syntax highlighting colors.
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

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        textView.backgroundColor = theme.backgroundColor
        textView.textColor = theme.foregroundColor
        textView.insertionPointColor = theme.foregroundColor
        scrollView.backgroundColor = theme.backgroundColor
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.backgroundColor.cgColor
    }

    // MARK: - Gutter

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        lineNumberGutter.needsDisplay = true
    }

    private func refreshGutter() {
        lineNumberGutter.updateWidth()
        lineNumberGutter.needsDisplay = true
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        lineNumberGutter.needsDisplay = true
        updateBracketHighlight()
        reportCursorPosition()
    }

    /// Computes line/column from the current selection and notifies the container.
    private func reportCursorPosition() {
        guard let callback = onSelectionChanged else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let location = selection.location

        // Count newlines before cursor to determine line number (1-based)
        let prefix = location <= text.length ? text.substring(to: location) : ""
        let line = prefix.components(separatedBy: "\n").count
        // Column = distance from last newline to cursor (1-based)
        let lastNewline = (prefix as NSString).range(
            of: "\n", options: .backwards
        ).location
        let column: Int
        if lastNewline == NSNotFound {
            column = location + 1
        } else {
            column = location - lastNewline
        }

        callback(line, column, selection.length)
    }

    @objc private func handleTextChange(_ notification: Notification) {
        refreshGutter()
        onTextChanged?(textView.string)
    }

    // MARK: - Warning Banner

    /// Shows a dismissible warning banner at the top of the editor.
    private func showWarningBanner(_ message: String) {
        let banner = NSView()
        banner.wantsLayer = true
        let theme = ThemeManager.shared.activeTheme
        banner.layer?.backgroundColor = theme.chromeBackground.cgColor
        banner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = FontManager.shared.activeFont.withSize(11)
        label.textColor = theme.paletteColor(at: 3)
        label.translatesAutoresizingMaskIntoConstraints = false

        let dismissButton = NSButton()
        dismissButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Dismiss warning"
        )
        dismissButton.bezelStyle = .accessoryBarAction
        dismissButton.isBordered = false
        dismissButton.contentTintColor = theme.paletteColor(at: 3)
        dismissButton.target = self
        dismissButton.action = #selector(dismissWarningBannerClicked)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(label)
        banner.addSubview(dismissButton)
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -8),
            dismissButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 16),
            dismissButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        warningBanner = banner
    }

    @objc private func dismissWarningBannerClicked() {
        dismissWarningBanner()
    }

    private func dismissWarningBanner() {
        warningBanner?.removeFromSuperview()
        warningBanner = nil
    }

    // MARK: - NSTextViewDelegate (Editing Behaviors)

    /// Intercepts key commands for auto-indent (all modes) and markdown list continuation.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if isMarkdownMode {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleMarkdownReturn(in: textView)
            case #selector(NSResponder.insertTab(_:)):
                return handleMarkdownTab(in: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return handleMarkdownBacktab(in: textView)
            default:
                return false
            }
        }

        // Code mode: auto-indent on Return
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return handleCodeAutoIndent(in: textView)
        }

        return false
    }

    // MARK: - Code Auto-Indent

    /// Handles Return in code mode: inserts a newline followed by the current line's
    /// leading whitespace. Increases indent by one level after lines ending with
    /// an opening brace, bracket, parenthesis, or colon (for YAML/Python).
    private func handleCodeAutoIndent(in textView: NSTextView) -> Bool {
        let text = textView.string as NSString
        let selectedRange = textView.selectedRange()

        // Get the current line up to the cursor position
        let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let lineUpToCursor = text.substring(
            with: NSRange(location: lineRange.location,
                          length: selectedRange.location - lineRange.location)
        )

        // Extract leading whitespace from the current line
        let leadingWhitespace: String
        if let wsRange = lineUpToCursor.range(of: #"^\s*"#, options: .regularExpression) {
            leadingWhitespace = String(lineUpToCursor[wsRange])
        } else {
            leadingWhitespace = ""
        }

        // Check if the line (trimmed, up to cursor) ends with an indent-increasing character
        let trimmed = lineUpToCursor.trimmingCharacters(in: .whitespaces)
        let lastChar = trimmed.last
        let shouldIncrease = lastChar == "{" || lastChar == "[" || lastChar == "(" || lastChar == ":"

        // Build the indentation for the new line
        let extraIndent = shouldIncrease ? detectIndentUnit(in: text) : ""
        let insertion = "\n" + leadingWhitespace + extraIndent

        textView.shouldChangeText(in: selectedRange, replacementString: insertion)
        textView.textStorage?.replaceCharacters(in: selectedRange, with: insertion)
        textView.didChangeText()

        let newCursor = selectedRange.location + (insertion as NSString).length
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))

        return true
    }

    /// Detects the indent unit used in the document by scanning the first
    /// indented line. Falls back to 4 spaces.
    private func detectIndentUnit(in text: NSString) -> String {
        let length = min(text.length, 8000) // scan a reasonable prefix
        let sample = text.substring(to: length)
        for line in sample.components(separatedBy: .newlines) {
            guard let first = line.first, first == " " || first == "\t" else { continue }
            if first == "\t" { return "\t" }
            // Count leading spaces
            let spaces = line.prefix(while: { $0 == " " }).count
            if spaces > 0 {
                return String(repeating: " ", count: min(spaces, 8))
            }
        }
        return "    " // default: 4 spaces
    }

    // MARK: - Bracket & Tag Matching

    /// Clears previous highlights and applies new ones based on cursor position.
    /// Checks bracket pairs first (`{}`, `[]`, `()`), then HTML/XML tag pairs
    /// for html/xml languages. No-op in markdown mode.
    /// Uses temporary attributes on the layout manager so highlights don't
    /// interfere with syntax highlighting or the undo stack.
    private func updateBracketHighlight() {
        guard !isMarkdownMode,
              let layoutManager = textView.layoutManager
        else { return }

        let textLength = textView.textStorage?.length ?? 0

        // Clear previous highlights
        for range in bracketHighlightRanges {
            if range.location + range.length <= textLength {
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor, forCharacterRange: range
                )
            }
        }
        bracketHighlightRanges.removeAll()

        let cursorPos = textView.selectedRange().location
        let theme = ThemeManager.shared.activeTheme

        // Try bracket matching first
        if let result = BracketMatcher.findMatch(
            in: textView.string, cursorPosition: cursorPos
        ) {
            let bracketRange = NSRange(location: result.bracketIndex, length: 1)

            if let matchIdx = result.matchIndex {
                let matchRange = NSRange(location: matchIdx, length: 1)
                let color = Self.matchedHighlightColor(from: theme)
                applyHighlight(color, to: [bracketRange, matchRange], layoutManager: layoutManager)
            } else {
                let color = Self.unmatchedHighlightColor(from: theme)
                applyHighlight(color, to: [bracketRange], layoutManager: layoutManager)
            }
            return
        }

        // Try HTML/XML tag matching
        if let tagResult = BracketMatcher.findTagMatch(
            in: textView.string as NSString,
            cursorPosition: cursorPos,
            language: currentLanguage
        ) {
            let sourceRange = tagResult.tagNameRange
            if let matchRange = tagResult.matchTagNameRange {
                let color = Self.matchedHighlightColor(from: theme)
                applyHighlight(color, to: [sourceRange, matchRange], layoutManager: layoutManager)
            } else {
                let color = Self.unmatchedHighlightColor(from: theme)
                applyHighlight(color, to: [sourceRange], layoutManager: layoutManager)
            }
        }
    }

    /// Applies a background highlight to the given ranges and tracks them for later removal.
    private func applyHighlight(
        _ color: NSColor,
        to ranges: [NSRange],
        layoutManager: NSLayoutManager
    ) {
        for range in ranges {
            layoutManager.addTemporaryAttribute(
                .backgroundColor, value: color, forCharacterRange: range
            )
        }
        bracketHighlightRanges = ranges
    }

    /// Derives the matched highlight color from the active theme.
    /// Uses the theme's accent color (palette blue) at 30% opacity.
    private static func matchedHighlightColor(from theme: Theme) -> NSColor {
        theme.paletteColor(at: 4).withAlphaComponent(0.3)
    }

    /// Derives the unmatched highlight color from the active theme.
    /// Uses the theme's red palette color at 30% opacity.
    private static func unmatchedHighlightColor(from theme: Theme) -> NSColor {
        theme.paletteColor(at: 1).withAlphaComponent(0.3)
    }

    // MARK: - Status Bar Actions

    /// Reopens the current file with a different encoding.
    /// Discards unsaved changes and resets the undo stack.
    func reopenWithEncoding(_ encoding: String.Encoding) {
        guard let url = currentFileURL else { return }
        fileEncoding = encoding
        guard let contents = try? String(contentsOf: url, encoding: encoding) else {
            NSLog("Cannot read file with encoding: \(EncodingInfo.displayName(for: encoding))")
            return
        }
        textView.undoManager?.removeAllActions()
        textView.string = contents
        lineEndings = FileEncodingDetector.detectLineEndings(in: contents)
        indentStyle = FileEncodingDetector.detectIndentStyle(in: contents)
        syntaxHighlighter?.highlightAll()
        refreshGutter()
        onFileMetadataChanged?()
        onSelectionChanged?(1, 1, 0)
    }

    /// Sets the encoding to use on next save without re-reading the file.
    func setEncodingForSave(_ encoding: String.Encoding) {
        fileEncoding = encoding
        onFileMetadataChanged?()
    }

    /// Converts all line endings in the document to the specified type.
    /// Operates on the in-memory text and marks the document as dirty.
    func convertLineEndings(to target: LineEnding) {
        guard target != lineEndings else { return }

        var text = textView.string
        // Normalize all line endings to LF first, then convert to target
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        if target != .lf {
            text = text.replacingOccurrences(of: "\n", with: target.characters)
        }

        textView.undoManager?.beginUndoGrouping()
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.insertText(text, replacementRange: fullRange)
        textView.undoManager?.endUndoGrouping()

        lineEndings = target
        syntaxHighlighter?.highlightAll()
        onFileMetadataChanged?()
    }

    /// Changes the indent style for future edits without converting existing indentation.
    func setIndentStyle(_ style: IndentStyle) {
        indentStyle = style
        onFileMetadataChanged?()
    }

    /// Converts all existing indentation in the document to the specified style.
    /// Also updates the active indent style for future edits.
    func convertIndentation(to target: IndentStyle) {
        let text = textView.string
        let lines = text.components(separatedBy: "\n")
        var converted: [String] = []

        // Determine current indent unit for conversion
        let currentUnit: String = switch indentStyle {
        case .spaces(let n): String(repeating: " ", count: n)
        case .tabs:          "\t"
        }

        let targetUnit = target.indentString

        for line in lines {
            // Count leading indent units
            var remaining = line[line.startIndex...]
            var indentCount = 0

            if case .tabs = indentStyle {
                // Current is tabs — count leading tabs
                while remaining.hasPrefix("\t") {
                    indentCount += 1
                    remaining = remaining.dropFirst()
                }
            } else {
                // Current is spaces — count leading space groups
                while remaining.hasPrefix(currentUnit) {
                    indentCount += 1
                    remaining = remaining.dropFirst(currentUnit.count)
                }
            }

            let newIndent = String(repeating: targetUnit, count: indentCount)
            converted.append(newIndent + remaining)
        }

        let result = converted.joined(separator: "\n")
        textView.undoManager?.beginUndoGrouping()
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.insertText(result, replacementRange: fullRange)
        textView.undoManager?.endUndoGrouping()

        indentStyle = target
        syntaxHighlighter?.highlightAll()
        onFileMetadataChanged?()
    }

    // MARK: - Word Wrap

    /// Toggles soft word wrap on or off.
    /// When on, text wraps at the view edge. When off, lines extend horizontally.
    func toggleWordWrap() {
        wordWrapEnabled.toggle()
        applyWordWrapSetting()
        onFileMetadataChanged?()
    }

    /// Configures the text view and scroll view for the current word wrap setting.
    private func applyWordWrapSetting() {
        guard let textView, let scrollView else { return }
        let contentWidth = scrollView.contentSize.width

        if wordWrapEnabled {
            // Shrink the text view frame back to the scroll view width so
            // widthTracksTextView can take over. Without this, the text container
            // stays infinitely wide from the no-wrap state.
            var frame = textView.frame
            frame.size.width = contentWidth
            textView.frame = frame

            textView.textContainer?.containerSize = NSSize(
                width: contentWidth, height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
            )
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
            textView.minSize = NSSize(width: contentWidth, height: scrollView.contentSize.height)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
            )
            scrollView.hasHorizontalScroller = true
        }

        // Force complete relayout
        textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        textView.needsDisplay = true
        refreshGutter()
    }
}
