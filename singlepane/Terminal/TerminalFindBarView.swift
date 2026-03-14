// TerminalFindBarView.swift
// Always-visible search bar for terminal sessions.
// Provides a text field, prev/next navigation, and a live match counter.

import AppKit

// MARK: - Delegate

/// Communicates find bar user actions to the terminal container.
@MainActor
protocol TerminalFindBarDelegate: AnyObject {
    func findBarSearchTextDidChange(_ text: String)
    func findBarDidRequestNextMatch()
    func findBarDidRequestPreviousMatch()
    func findBarDidRequestFocusTerminal()
}

// MARK: - View

@MainActor
final class TerminalFindBarView: NSView, NSTextFieldDelegate {

    weak var delegate: TerminalFindBarDelegate?

    /// The current search text — read by the container to save/restore per-session state.
    var searchText: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    // MARK: - Subviews

    private let searchField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Find in terminal…"
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

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
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
        for button in [prevButton, nextButton, clearButton] where !button.isHidden {
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

    /// Fixed height for the find bar strip.
    static let barHeight: CGFloat = 34

    private func setupSubviews() {
        wantsLayer = true

        searchField.delegate = self
        addSubview(searchField)

        prevButton.target = self
        prevButton.action = #selector(prevButtonClicked)
        addSubview(prevButton)

        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
        addSubview(nextButton)

        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        addSubview(clearButton)

        addSubview(counterLabel)

        NSLayoutConstraint.activate([
            // Search field — takes available space, with horizontal padding
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Clear button — right of search field, visible only when text is present
            clearButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),

            // Counter label — right of clear button
            counterLabel.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 4),
            counterLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Previous button
            prevButton.leadingAnchor.constraint(equalTo: counterLabel.trailingAnchor, constant: 2),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 24),

            // Next button
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 0),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 24),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    // MARK: - Focus

    /// Makes the search field the first responder so keyboard input stays in the find bar.
    func focus() {
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Counter

    /// Updates the match counter display.
    /// - Parameters:
    ///   - current: 1-based index of the current match, or 0 if no matches.
    ///   - total: Total number of matches found.
    func updateCounter(current: Int, total: Int) {
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
        delegate?.findBarDidRequestPreviousMatch()
    }

    @objc private func nextButtonClicked() {
        delegate?.findBarDidRequestNextMatch()
    }

    @objc private func clearButtonClicked() {
        searchField.stringValue = ""
        clearButton.isHidden = true
        delegate?.findBarSearchTextDidChange("")
    }

    // MARK: - NSTextFieldDelegate

    /// Live search on every keystroke. Shows/hides clear button based on text presence.
    func controlTextDidChange(_ obj: Notification) {
        clearButton.isHidden = searchField.stringValue.isEmpty
        delegate?.findBarSearchTextDidChange(searchField.stringValue)
    }

    /// Intercept Enter, Shift+Enter, and Escape for navigation and focus control.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Enter → next match
            delegate?.findBarDidRequestNextMatch()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Escape → return focus to terminal
            delegate?.findBarDidRequestFocusTerminal()
            return true
        default:
            return false
        }
    }

    /// Shift+Enter is not a standard command selector — override keyDown to catch it.
    override func keyDown(with event: NSEvent) {
        let isShiftReturn = event.keyCode == 36 && event.modifierFlags.contains(.shift)
        if isShiftReturn {
            delegate?.findBarDidRequestPreviousMatch()
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
    }
}
