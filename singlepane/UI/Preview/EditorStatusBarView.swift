// EditorStatusBarView.swift
// Thin status bar at the bottom of the editor showing cursor position,
// file encoding, line endings, indentation style, and language.
//
// Layout:
//   Left:  cursor position (Ln X, Col Y)  |  selection info (when selected)
//   Right: encoding button | line endings button | indent button | language label
//
// All items except language are clickable, showing popover menus for changing values.
// Owned by PreviewContainerViewController, which controls visibility and data flow.

import AppKit

// MARK: - Delegate

/// Communicates status bar user actions to the preview container.
@MainActor
protocol EditorStatusBarDelegate: AnyObject {
    func statusBarDidRequestEncodingMenu(from button: NSView)
    func statusBarDidRequestLineEndingMenu(from button: NSView)
    func statusBarDidRequestIndentMenu(from button: NSView)
    func statusBarDidToggleWordWrap()
}

// MARK: - View

@MainActor
final class EditorStatusBarView: NSView {

    weak var delegate: EditorStatusBarDelegate?

    /// Fixed height for the status bar.
    static let barHeight: CGFloat = 20

    // MARK: - Left Side

    private let cursorLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Ln 1, Col 1")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.controlSize = .small
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private let selectionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.controlSize = .small
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.isHidden = true
        return label
    }()

    /// Separator between cursor and selection labels.
    private let selectionSeparator: NSTextField = {
        let label = NSTextField(labelWithString: "|")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.controlSize = .small
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.isHidden = true
        return label
    }()

    // MARK: - Right Side

    private let encodingButton: NSButton = {
        let btn = NSButton(title: "UTF-8", target: nil, action: nil)
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.controlSize = .small
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let lineEndingButton: NSButton = {
        let btn = NSButton(title: "LF", target: nil, action: nil)
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.controlSize = .small
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let indentButton: NSButton = {
        let btn = NSButton(title: "Spaces: 4", target: nil, action: nil)
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.controlSize = .small
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let wordWrapButton: NSButton = {
        let btn = NSButton(title: "Word Wrap", target: nil, action: nil)
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.controlSize = .small
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let languageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Text")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.controlSize = .small
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    /// Thin separator lines between right-side items.
    private func makeSeparator() -> NSTextField {
        let label = NSTextField(labelWithString: "|")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.controlSize = .small
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private var rightSeparators: [NSTextField] = []

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayout()
        applyTheme()
        applyFont()
        startObservingTheme()
        startObservingFont()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        for button in [encodingButton, lineEndingButton, indentButton, wordWrapButton] where !button.isHidden {
            let rect = convert(button.bounds, from: button)
            addTrackingArea(NSTrackingArea(
                rect: rect,
                options: [.cursorUpdate, .activeInActiveApp],
                owner: self
            ))
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    // MARK: - Layout

    private func setupLayout() {
        wantsLayer = true

        // Wire button targets
        encodingButton.target = self
        encodingButton.action = #selector(encodingButtonClicked)
        lineEndingButton.target = self
        lineEndingButton.action = #selector(lineEndingButtonClicked)
        indentButton.target = self
        indentButton.action = #selector(indentButtonClicked)
        wordWrapButton.target = self
        wordWrapButton.action = #selector(wordWrapButtonClicked)

        // Add left-side views
        addSubview(cursorLabel)
        addSubview(selectionSeparator)
        addSubview(selectionLabel)

        // Add right-side views with separators
        // Right-to-left: language | indent | line ending | encoding | word wrap
        addSubview(languageLabel)
        let sep1 = makeSeparator()
        addSubview(sep1)
        addSubview(indentButton)
        let sep2 = makeSeparator()
        addSubview(sep2)
        addSubview(lineEndingButton)
        let sep3 = makeSeparator()
        addSubview(sep3)
        addSubview(encodingButton)
        let sep4 = makeSeparator()
        addSubview(sep4)
        addSubview(wordWrapButton)
        rightSeparators = [sep1, sep2, sep3, sep4]

        NSLayoutConstraint.activate([
            // Left side: cursor position
            cursorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cursorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Selection separator + label (hidden when no selection)
            selectionSeparator.leadingAnchor.constraint(equalTo: cursorLabel.trailingAnchor, constant: 6),
            selectionSeparator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionLabel.leadingAnchor.constraint(equalTo: selectionSeparator.trailingAnchor, constant: 6),
            selectionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Right side: language (rightmost)
            languageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            languageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Separator | indent button
            sep1.trailingAnchor.constraint(equalTo: languageLabel.leadingAnchor, constant: -6),
            sep1.centerYAnchor.constraint(equalTo: centerYAnchor),
            indentButton.trailingAnchor.constraint(equalTo: sep1.leadingAnchor, constant: -6),
            indentButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Separator | line ending button
            sep2.trailingAnchor.constraint(equalTo: indentButton.leadingAnchor, constant: -6),
            sep2.centerYAnchor.constraint(equalTo: centerYAnchor),
            lineEndingButton.trailingAnchor.constraint(equalTo: sep2.leadingAnchor, constant: -6),
            lineEndingButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Separator | encoding button
            sep3.trailingAnchor.constraint(equalTo: lineEndingButton.leadingAnchor, constant: -6),
            sep3.centerYAnchor.constraint(equalTo: centerYAnchor),
            encodingButton.trailingAnchor.constraint(equalTo: sep3.leadingAnchor, constant: -6),
            encodingButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Separator | word wrap button
            sep4.trailingAnchor.constraint(equalTo: encodingButton.leadingAnchor, constant: -6),
            sep4.centerYAnchor.constraint(equalTo: centerYAnchor),
            wordWrapButton.trailingAnchor.constraint(equalTo: sep4.leadingAnchor, constant: -6),
            wordWrapButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Update Methods

    /// Updates the cursor position display. Line and column are 1-based.
    /// Shows selection info when selectionLength > 0.
    func updateCursorPosition(line: Int, column: Int, selectionLength: Int) {
        cursorLabel.stringValue = "Ln \(line), Col \(column)"

        if selectionLength > 0 {
            selectionLabel.stringValue = "\(selectionLength) selected"
            selectionLabel.isHidden = false
            selectionSeparator.isHidden = false
        } else {
            selectionLabel.isHidden = true
            selectionSeparator.isHidden = true
        }
    }

    /// Updates the encoding display.
    func updateEncoding(_ encoding: String.Encoding) {
        encodingButton.title = EncodingInfo.displayName(for: encoding)
    }

    /// Updates the line ending display.
    func updateLineEndings(_ lineEnding: LineEnding) {
        lineEndingButton.title = lineEnding.rawValue
    }

    /// Updates the indentation style display.
    func updateIndentStyle(_ style: IndentStyle) {
        indentButton.title = style.displayName
    }

    /// Updates the language display with a human-readable name.
    func updateLanguage(_ languageID: String) {
        languageLabel.stringValue = Self.displayName(for: languageID)
    }

    /// Updates the word wrap button to reflect the current state.
    func updateWordWrap(_ enabled: Bool) {
        wordWrapButton.title = enabled ? "Word Wrap" : "No Wrap"
    }

    // MARK: - Button Actions

    @objc private func encodingButtonClicked() {
        delegate?.statusBarDidRequestEncodingMenu(from: encodingButton)
    }

    @objc private func lineEndingButtonClicked() {
        delegate?.statusBarDidRequestLineEndingMenu(from: lineEndingButton)
    }

    @objc private func indentButtonClicked() {
        delegate?.statusBarDidRequestIndentMenu(from: indentButton)
    }

    @objc private func wordWrapButtonClicked() {
        delegate?.statusBarDidToggleWordWrap()
    }

    // MARK: - Theme

    private func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.startObservingTheme()
            }
        }
    }

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = theme.chromeBackground.cgColor

        let textColor = theme.chromeTextSecondary
        let separatorColor = textColor.withAlphaComponent(0.3)

        cursorLabel.textColor = textColor
        selectionLabel.textColor = textColor
        selectionSeparator.textColor = separatorColor
        languageLabel.textColor = textColor
        encodingButton.contentTintColor = textColor
        lineEndingButton.contentTintColor = textColor
        indentButton.contentTintColor = textColor
        wordWrapButton.contentTintColor = textColor

        for sep in rightSeparators {
            sep.textColor = separatorColor
        }
    }

    // MARK: - Font

    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.startObservingFont()
            }
        }
    }

    private func applyFont() {
        let font = FontManager.shared.activeFont.withSize(10)
        cursorLabel.font = font
        selectionLabel.font = font
        selectionSeparator.font = font
        languageLabel.font = font
        encodingButton.font = font
        lineEndingButton.font = font
        indentButton.font = font
        wordWrapButton.font = font

        for sep in rightSeparators {
            sep.font = font
        }
    }

    // MARK: - Language Display Names

    /// Maps internal language identifiers to human-readable names for the status bar.
    private static func displayName(for languageID: String) -> String {
        switch languageID {
        case "json":     "JSON"
        case "yaml":     "YAML"
        case "toml":     "TOML"
        case "xml":      "XML"
        case "html":     "HTML"
        case "css":      "CSS"
        case "swift":    "Swift"
        case "js":       "JavaScript"
        case "python":   "Python"
        case "ruby":     "Ruby"
        case "rust":     "Rust"
        case "go":       "Go"
        case "shell":    "Shell"
        case "sql":      "SQL"
        case "c":        "C/C++"
        case "java":     "Java"
        case "csharp":   "C#"
        case "lua":      "Lua"
        case "markdown": "Markdown"
        case "text":     "Plain Text"
        default:         languageID.capitalized
        }
    }
}
