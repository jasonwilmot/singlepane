// ContentFindBarView.swift
// Always-visible search bar for the content/preview panel.
// Provides a text field, prev/next navigation, a live match counter,
// and a toggleable replace row for editor mode.
// Mirrors TerminalFindBarView for visual consistency across panels.

import AppKit

// MARK: - Delegate

/// Communicates find bar user actions to the preview container.
@MainActor
protocol ContentFindBarDelegate: AnyObject {
    func contentFindBarSearchTextDidChange(_ text: String)
    func contentFindBarDidRequestNextMatch()
    func contentFindBarDidRequestPreviousMatch()
    func contentFindBarDidRequestFocusContent()
    func contentFindBarDidRequestReplace(_ replacementText: String)
    func contentFindBarDidRequestReplaceAll(_ replacementText: String)
}

// MARK: - View

@MainActor
final class ContentFindBarView: NSView, NSTextFieldDelegate {

    weak var delegate: ContentFindBarDelegate?

    /// The current search text — read by the container to save/restore state.
    var searchText: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    /// The current replacement text.
    var replaceText: String {
        get { replaceField.stringValue }
        set { replaceField.stringValue = newValue }
    }

    /// Whether the replace row is currently visible.
    private(set) var isReplaceVisible = false

    /// Called when the replace row visibility changes so the parent can update layout.
    var onReplaceVisibilityChanged: (() -> Void)?

    // MARK: - Search Toggle State

    /// Whether regex matching is active.
    private(set) var isRegexEnabled = false

    /// Whether case-sensitive matching is active.
    private(set) var isCaseSensitive = false

    /// Whether whole-word matching is active.
    private(set) var isWholeWord = false

    // MARK: - Heights

    /// Height when showing find row only.
    static let findOnlyHeight: CGFloat = 34

    /// Height when showing both find and replace rows.
    static let findAndReplaceHeight: CGFloat = 68

    /// Current height based on replace row visibility.
    var currentHeight: CGFloat {
        isReplaceVisible ? Self.findAndReplaceHeight : Self.findOnlyHeight
    }

    // MARK: - Find Row Subviews

    private let searchField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Find in content…"
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.controlSize = .regular
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let prevButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private let nextButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    /// Clear button overlaid inside the search field, right-aligned.
    private let clearButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Clear search"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.isHidden = true // Hidden until text is entered
        return button
    }()

    private let counterLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .right
        label.controlSize = .small
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Toggle button to show/hide the replace row. Only visible in editor mode.
    private let replaceToggleButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "arrow.2.squarepath",
            accessibilityDescription: "Toggle replace"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.isHidden = true // Hidden until editor mode
        return button
    }()

    // MARK: - Search Toggle Buttons

    /// Regex toggle — uses `.*` text label for clarity.
    private let regexToggle: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "ellipsis.curlybraces",
            accessibilityDescription: "Toggle regex"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setButtonType(.toggle)
        button.toolTip = "Regex"
        return button
    }()

    /// Case-sensitive toggle — Aa icon.
    private let caseSensitiveToggle: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "textformat",
            accessibilityDescription: "Toggle case sensitivity"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setButtonType(.toggle)
        button.toolTip = "Case Sensitive"
        return button
    }()

    /// Whole-word toggle — word boundary icon.
    private let wholeWordToggle: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "textformat.abc",
            accessibilityDescription: "Toggle whole word"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setButtonType(.toggle)
        button.toolTip = "Whole Word"
        return button
    }()

    // MARK: - Replace Row Subviews

    /// Container for the replace row — hidden by default, shown via toggle.
    private let replaceRow: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let replaceField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Replace…"
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.controlSize = .regular
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// Clear button overlaid inside the replace field, right-aligned.
    private let replaceClearButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Clear replace"
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.isHidden = true
        return button
    }()

    private let replaceButton: NSButton = {
        let button = NSButton(title: "Replace", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private let replaceAllButton: NSButton = {
        let button = NSButton(title: "All", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupFindRow()
        setupReplaceRow()
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

    override func resetCursorRects() {
        super.resetCursorRects()
        let buttons: [NSButton] = [
            prevButton, nextButton, clearButton, replaceToggleButton,
            regexToggle, caseSensitiveToggle, wholeWordToggle,
            replaceClearButton, replaceButton, replaceAllButton,
        ]
        for button in buttons where !button.isHidden {
            // Discard the button's own cursor rects so it doesn't reset to arrow
            button.discardCursorRects()
            let rect = convert(button.bounds, from: button)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    // MARK: - Find Row Layout

    private func setupFindRow() {
        wantsLayer = true

        searchField.delegate = self
        addSubview(searchField)

        // Clear button overlaid inside the search field
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        addSubview(clearButton)

        replaceToggleButton.target = self
        replaceToggleButton.action = #selector(replaceToggleClicked)
        addSubview(replaceToggleButton)

        prevButton.target = self
        prevButton.action = #selector(prevButtonClicked)
        addSubview(prevButton)

        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
        addSubview(nextButton)

        addSubview(counterLabel)

        // Search toggle buttons — between search field and counter label
        regexToggle.target = self
        regexToggle.action = #selector(searchToggleClicked(_:))
        addSubview(regexToggle)

        caseSensitiveToggle.target = self
        caseSensitiveToggle.action = #selector(searchToggleClicked(_:))
        addSubview(caseSensitiveToggle)

        wholeWordToggle.target = self
        wholeWordToggle.action = #selector(searchToggleClicked(_:))
        addSubview(wholeWordToggle)

        let rowCenterY = Self.findOnlyHeight / 2

        NSLayoutConstraint.activate([
            // Replace toggle — leftmost element
            replaceToggleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            replaceToggleButton.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            replaceToggleButton.widthAnchor.constraint(equalToConstant: 20),

            // Search field — takes available space up to the toggle buttons
            searchField.leadingAnchor.constraint(equalTo: replaceToggleButton.trailingAnchor, constant: 2),
            searchField.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),

            // Clear button — overlaid inside the search field, right-aligned
            clearButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: -2),
            clearButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),

            // Regex toggle — right of search field
            regexToggle.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            regexToggle.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            regexToggle.widthAnchor.constraint(equalToConstant: 22),

            // Case-sensitive toggle
            caseSensitiveToggle.leadingAnchor.constraint(equalTo: regexToggle.trailingAnchor, constant: 0),
            caseSensitiveToggle.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            caseSensitiveToggle.widthAnchor.constraint(equalToConstant: 22),

            // Whole-word toggle
            wholeWordToggle.leadingAnchor.constraint(equalTo: caseSensitiveToggle.trailingAnchor, constant: 0),
            wholeWordToggle.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            wholeWordToggle.widthAnchor.constraint(equalToConstant: 22),

            // Counter label — right of toggle buttons
            counterLabel.leadingAnchor.constraint(equalTo: wholeWordToggle.trailingAnchor, constant: 4),
            counterLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Previous button
            prevButton.leadingAnchor.constraint(equalTo: counterLabel.trailingAnchor, constant: 2),
            prevButton.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            prevButton.widthAnchor.constraint(equalToConstant: 24),

            // Next button
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 0),
            nextButton.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenterY),
            nextButton.widthAnchor.constraint(equalToConstant: 24),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    // MARK: - Replace Row Layout

    private func setupReplaceRow() {
        addSubview(replaceRow)

        replaceField.delegate = self
        replaceRow.addSubview(replaceField)

        // Clear button overlaid inside the replace field
        replaceClearButton.target = self
        replaceClearButton.action = #selector(replaceClearButtonClicked)
        replaceRow.addSubview(replaceClearButton)

        replaceButton.target = self
        replaceButton.action = #selector(replaceButtonClicked)
        replaceRow.addSubview(replaceButton)

        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAllButtonClicked)
        replaceRow.addSubview(replaceAllButton)

        NSLayoutConstraint.activate([
            // Replace row sits below the find row
            replaceRow.topAnchor.constraint(equalTo: topAnchor, constant: Self.findOnlyHeight),
            replaceRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            replaceRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            replaceRow.heightAnchor.constraint(
                equalToConstant: Self.findAndReplaceHeight - Self.findOnlyHeight
            ),

            // Replace field — same leading/trailing as the search field above
            replaceField.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            replaceField.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            replaceField.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            // Clear button — overlaid inside the replace field, right-aligned
            replaceClearButton.trailingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: -2),
            replaceClearButton.centerYAnchor.constraint(equalTo: replaceField.centerYAnchor),
            replaceClearButton.widthAnchor.constraint(equalToConstant: 16),
            replaceClearButton.heightAnchor.constraint(equalToConstant: 16),

            // Replace All button — anchored to trailing edge
            replaceAllButton.trailingAnchor.constraint(equalTo: replaceRow.trailingAnchor, constant: -8),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            // Replace button — left of Replace All
            replaceButton.trailingAnchor.constraint(equalTo: replaceAllButton.leadingAnchor, constant: -2),
            replaceButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),
        ])
    }

    // MARK: - Replace Visibility

    /// Shows the replace row and notifies the parent to update layout.
    func showReplace() {
        guard !isReplaceVisible else { return }
        isReplaceVisible = true
        replaceRow.isHidden = false
        onReplaceVisibilityChanged?()
    }

    /// Hides the replace row and notifies the parent to update layout.
    func hideReplace() {
        guard isReplaceVisible else { return }
        isReplaceVisible = false
        replaceRow.isHidden = true
        onReplaceVisibilityChanged?()
    }

    /// Shows or hides the replace toggle icon based on whether replace is allowed.
    /// Called by the parent when switching between editor and non-editor modes.
    func setReplaceEnabled(_ enabled: Bool) {
        replaceToggleButton.isHidden = !enabled
        if !enabled {
            hideReplace()
        }
    }

    /// Focuses the replace field for keyboard input.
    func focusReplaceField() {
        window?.makeFirstResponder(replaceField)
    }

    // MARK: - Counter

    /// Updates the match counter display.
    /// - Parameters:
    ///   - current: 1-based index of the current match, or 0 if no matches.
    ///   - total: Total number of matches found.
    func updateCounter(current: Int, total: Int) {
        resetCounterStyle()
        if searchField.stringValue.isEmpty {
            counterLabel.stringValue = ""
        } else if total == 0 {
            counterLabel.stringValue = "0 of 0"
        } else {
            counterLabel.stringValue = "\(current) of \(total)"
        }
    }

    // MARK: - Actions

    @objc private func prevButtonClicked() {
        delegate?.contentFindBarDidRequestPreviousMatch()
    }

    @objc private func nextButtonClicked() {
        delegate?.contentFindBarDidRequestNextMatch()
    }

    @objc private func clearButtonClicked() {
        searchField.stringValue = ""
        clearButton.isHidden = true
        delegate?.contentFindBarSearchTextDidChange("")
    }

    @objc private func replaceClearButtonClicked() {
        replaceField.stringValue = ""
        replaceClearButton.isHidden = true
    }

    @objc private func replaceToggleClicked() {
        if isReplaceVisible {
            hideReplace()
        } else {
            showReplace()
            focusReplaceField()
        }
    }

    @objc private func replaceButtonClicked() {
        delegate?.contentFindBarDidRequestReplace(replaceField.stringValue)
    }

    @objc private func replaceAllButtonClicked() {
        delegate?.contentFindBarDidRequestReplaceAll(replaceField.stringValue)
    }

    /// Handles toggle state changes for regex, case-sensitive, and whole-word buttons.
    /// Updates internal state, applies highlight styling, and re-triggers search.
    @objc private func searchToggleClicked(_ sender: NSButton) {
        if sender === regexToggle {
            isRegexEnabled = sender.state == .on
        } else if sender === caseSensitiveToggle {
            isCaseSensitive = sender.state == .on
        } else if sender === wholeWordToggle {
            isWholeWord = sender.state == .on
        }
        applyToggleHighlights()
        delegate?.contentFindBarSearchTextDidChange(searchField.stringValue)
    }

    /// Focuses the search field for keyboard input.
    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    /// Shows an error state in the counter label (e.g. for invalid regex).
    func showError(_ message: String) {
        counterLabel.stringValue = message
        counterLabel.textColor = .systemRed
    }

    /// Resets the counter label text color to normal after an error state.
    private func resetCounterStyle() {
        counterLabel.textColor = ThemeManager.shared.activeTheme.chromeTextSecondary
    }

    // MARK: - NSTextFieldDelegate

    /// Live search on every keystroke. Shows/hides clear buttons based on text presence.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === searchField {
            clearButton.isHidden = searchField.stringValue.isEmpty
            delegate?.contentFindBarSearchTextDidChange(searchField.stringValue)
        } else if field === replaceField {
            replaceClearButton.isHidden = replaceField.stringValue.isEmpty
        }
    }

    /// Intercept Enter, Shift+Enter, and Escape for navigation and focus control.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if control === searchField {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                delegate?.contentFindBarDidRequestNextMatch()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if isReplaceVisible {
                    hideReplace()
                } else {
                    delegate?.contentFindBarDidRequestFocusContent()
                }
                return true
            default:
                return false
            }
        } else if control === replaceField {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                // Enter in replace field → replace current match
                delegate?.contentFindBarDidRequestReplace(replaceField.stringValue)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape in replace field → hide replace row
                hideReplace()
                focusSearchField()
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Shift+Enter is not a standard command selector — override keyDown to catch it.
    override func keyDown(with event: NSEvent) {
        let isShiftReturn = event.keyCode == 36 && event.modifierFlags.contains(.shift)
        if isShiftReturn {
            delegate?.contentFindBarDidRequestPreviousMatch()
            return
        }
        super.keyDown(with: event)
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
        searchField.textColor = theme.chromeText
        searchField.backgroundColor = theme.backgroundColor
        counterLabel.textColor = theme.chromeTextSecondary
        clearButton.contentTintColor = theme.chromeTextSecondary
        prevButton.contentTintColor = theme.chromeText
        nextButton.contentTintColor = theme.chromeText
        replaceToggleButton.contentTintColor = theme.chromeText
        replaceField.textColor = theme.chromeText
        replaceField.backgroundColor = theme.backgroundColor
        replaceClearButton.contentTintColor = theme.chromeTextSecondary
        replaceButton.contentTintColor = theme.chromeText
        replaceAllButton.contentTintColor = theme.chromeText
        applyToggleHighlights()
    }

    /// Applies highlight styling to search toggle buttons based on their active state.
    /// Active toggles get a tinted background and accent color; inactive use standard chrome text.
    private func applyToggleHighlights() {
        let theme = ThemeManager.shared.activeTheme
        let accentColor = theme.paletteColor(at: 4)

        for (button, isActive) in [
            (regexToggle, isRegexEnabled),
            (caseSensitiveToggle, isCaseSensitive),
            (wholeWordToggle, isWholeWord),
        ] {
            button.wantsLayer = true
            if isActive {
                button.layer?.backgroundColor = accentColor.withAlphaComponent(0.3).cgColor
                button.contentTintColor = accentColor
                button.layer?.cornerRadius = 4
            } else {
                button.layer?.backgroundColor = nil
                button.contentTintColor = theme.chromeText
            }
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
        let font = FontManager.shared.activeFont.withSize(11)
        searchField.font = font
        counterLabel.font = font
        replaceField.font = font
    }
}
