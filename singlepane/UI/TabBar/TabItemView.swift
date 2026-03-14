// TabItemView.swift
// Individual tab in the custom tab bar.
// Displays status indicator, title, selection highlight, and close "x" button.
// Status indicator: asterisk (*) at rest, animated spinner when busy.

import AppKit

@MainActor
final class TabItemView: NSView {

    // MARK: - Style

    /// Controls which chrome elements appear on the tab.
    enum Style {
        /// Full tab with status indicator and close button (terminal, file explorer).
        case full
        /// Compact tab with title only — no status indicator or close button (preview modes).
        case compact
    }

    // MARK: - Orientation Mode

    /// Controls whether the tab renders as a horizontal tab (rounded top, open bottom)
    /// or a vertical row (full-width, no tab-shaped chrome).
    enum OrientationMode {
        case horizontal
        case vertical
    }

    // MARK: - Properties

    var index: Int
    /// Called when the tab is clicked. Bool is true when Cmd was held (multi-select).
    var onSelect: ((Int, Bool) -> Void)?
    var onClose: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?

    private let style: Style
    private var orientationMode: OrientationMode = .horizontal
    private let statusLabel = NSTextField(labelWithString: "\u{2731}") // asterisk ✱
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isSelected = false
    private var isFocused = false
    private var isSpinning = false
    private var spinnerTimer: Timer?

    /// Spinner frames — rotating braille characters for a compact animation.
    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerFrameIndex = 0

    /// Optional hook-driven highlight color (background wash).
    /// Set via singlepane:// URL scheme. Persists until changed by next hook event.
    private(set) var highlightColor: NSColor?

    // MARK: - Init

    init(title: String, index: Int, style: Style = .full) {
        self.index = index
        self.style = style
        super.init(frame: .zero)
        setupViews(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews(title: String) {
        wantsLayer = true
        layer?.cornerRadius = 4
        // Round only the top corners — NSView layers use bottom-left origin,
        // so maxY = top. Open bottom connects to content area.
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // Title label (always present)
        titleLabel.stringValue = title
        titleLabel.font = FontManager.shared.activeFont.withSize(11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        translatesAutoresizingMaskIntoConstraints = false

        switch style {
        case .full:
            setupFullStyle()
        case .compact:
            setupCompactStyle()
        }

        updateAppearance()
    }

    /// Stored layout constraints for full style — swapped on orientation mode change.
    private var fullStyleConstraints: [NSLayoutConstraint] = []

    /// Full style: status indicator + title + close button.
    private func setupFullStyle() {
        statusLabel.font = FontManager.shared.activeFont.withSize(9)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(statusLabel)

        closeButton.bezelStyle = .accessoryBarAction
        closeButton.title = "\u{2715}"
        closeButton.font = FontManager.shared.activeFont.withSize(9)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(closeButton)

        applyHorizontalTabConstraints()
    }

    /// Horizontal tab constraints: fixed height, bounded width, tab-shaped chrome.
    private func applyHorizontalTabConstraints() {
        fullStyleConstraints = [
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ]
        NSLayoutConstraint.activate(fullStyleConstraints)
    }

    /// Vertical row constraints: status indicator left-aligned, title and close button right-aligned,
    /// full-width separator.
    private func applyVerticalRowConstraints() {
        fullStyleConstraints = [
            heightAnchor.constraint(equalToConstant: 34),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ]
        NSLayoutConstraint.activate(fullStyleConstraints)
    }

    /// Compact style: centered title only — no status indicator or close button.
    private func setupCompactStyle() {
        titleLabel.alignment = .center

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - State

    func setSelected(_ selected: Bool) {
        isSelected = selected
        updateAppearance()
    }

    /// Marks this tab as the focused tab (thick accent border).
    /// In grouped mode only the focused tab gets this, not all selected tabs.
    func setFocused(_ focused: Bool) {
        isFocused = focused
        updateAppearance()
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    /// Switches between horizontal tab chrome and vertical row styling.
    /// Tears down existing constraints and re-applies for the new mode.
    func setOrientationMode(_ mode: OrientationMode) {
        guard style == .full, mode != orientationMode else { return }
        orientationMode = mode

        NSLayoutConstraint.deactivate(fullStyleConstraints)
        fullStyleConstraints.removeAll()

        switch mode {
        case .horizontal:
            statusLabel.isHidden = false
            titleLabel.alignment = .natural
            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            layer?.cornerRadius = 4
            layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            applyHorizontalTabConstraints()
        case .vertical:
            statusLabel.isHidden = false
            titleLabel.alignment = .right
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            layer?.cornerRadius = 0
            applyVerticalRowConstraints()
        }

        updateAppearance()
    }

    /// Apply a highlight color wash to this tab.
    func setHighlightColor(_ color: NSColor?) {
        highlightColor = color
        updateAppearance()
    }

    // MARK: - Spinner

    /// Start the animated spinner indicator (replaces the asterisk).
    func startSpinner() {
        guard !isSpinning else { return }
        isSpinning = true
        spinnerFrameIndex = 0
        statusLabel.stringValue = Self.spinnerFrames[0]

        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSpinning else { return }
                self.spinnerFrameIndex = (self.spinnerFrameIndex + 1) % Self.spinnerFrames.count
                self.statusLabel.stringValue = Self.spinnerFrames[self.spinnerFrameIndex]
            }
        }
    }

    /// Stop the spinner and restore the asterisk indicator.
    func stopSpinner() {
        guard isSpinning else { return }
        isSpinning = false
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        statusLabel.stringValue = "\u{2731}" // asterisk ✱
    }

    // MARK: - Font

    /// Re-applies the active font to all text elements.
    func applyFont() {
        let font = FontManager.shared.activeFont
        titleLabel.font = font.withSize(11)
        if style == .full {
            statusLabel.font = font.withSize(9)
            closeButton.font = font.withSize(9)
        }
    }

    // MARK: - Appearance

    private func updateAppearance() {
        let theme = ThemeManager.shared.activeTheme

        if let highlightColor {
            // Hook-driven highlight — subtle wash of the hook color
            layer?.backgroundColor = highlightColor.withAlphaComponent(0.25).cgColor
            titleLabel.textColor = theme.chromeText
            if style == .full { statusLabel.textColor = theme.chromeText }
        } else if isSelected {
            layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.2).cgColor
            titleLabel.textColor = theme.chromeText
            if style == .full { statusLabel.textColor = theme.chromeText }
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = theme.chromeTextSecondary
            if style == .full { statusLabel.textColor = theme.chromeTextSecondary }
        }

        // Focused tab gets a thicker accent border; others get a subtle default border.
        if isFocused {
            updateTabBorders(color: theme.chromeAccent.cgColor, thickness: 2)
        } else {
            updateTabBorders(
                color: theme.chromeText.withAlphaComponent(0.25).cgColor,
                thickness: 1
            )
        }
    }

    /// Draws border sublayers appropriate for the current orientation mode.
    /// Horizontal: 3-sided tab shape (left, right, top — open bottom).
    /// Vertical: single bottom separator line.
    private func updateTabBorders(color: CGColor, thickness: CGFloat = 1) {
        guard let layer else { return }

        // Remove previous border layers
        layer.sublayers?.removeAll { $0.name == "tabBorder" }

        let bounds = layer.bounds

        if orientationMode == .vertical {
            // Simple bottom separator for row style
            let bottom = CALayer()
            bottom.name = "tabBorder"
            bottom.frame = CGRect(x: 0, y: 0, width: bounds.width, height: thickness)
            bottom.backgroundColor = color
            layer.addSublayer(bottom)
        } else {
            // 3-sided tab shape: left, right, top — open at the bottom
            let left = CALayer()
            left.name = "tabBorder"
            left.frame = CGRect(x: 0, y: 0, width: thickness, height: bounds.height)
            left.backgroundColor = color

            let right = CALayer()
            right.name = "tabBorder"
            right.frame = CGRect(x: bounds.width - thickness, y: 0, width: thickness, height: bounds.height)
            right.backgroundColor = color

            let top = CALayer()
            top.name = "tabBorder"
            top.frame = CGRect(x: 0, y: bounds.height - thickness, width: bounds.width, height: thickness)
            top.backgroundColor = color

            layer.addSublayer(left)
            layer.addSublayer(right)
            layer.addSublayer(top)
        }
    }

    override func layout() {
        super.layout()
        // Re-position border layers when the view resizes.
        let theme = ThemeManager.shared.activeTheme
        if isFocused {
            updateTabBorders(color: theme.chromeAccent.cgColor, thickness: 2)
        } else {
            updateTabBorders(
                color: theme.chromeText.withAlphaComponent(0.25).cgColor,
                thickness: 1
            )
        }
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInActiveApp],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    // MARK: - Mouse Handling

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Custom hit testing ensures clicks reach this view, not its label subviews.
    /// NSTextField subviews can intercept mouse events and consume them silently.
    /// By returning self for all non-close-button clicks, we guarantee mouseDown
    /// is delivered to TabItemView for tab selection.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point is in superview's (NSStackView's) coordinate space
        guard !isHidden, frame.contains(point) else { return nil }

        let local = convert(point, from: superview)

        // Let the close button handle its own click events
        if style == .full && !closeButton.isHidden && closeButton.frame.contains(local) {
            return closeButton
        }

        // Return self for all other clicks — labels don't need mouse events
        return self
    }

    /// Handle tab selection directly on mouseDown.
    /// Using mouseDown instead of mouseUp avoids delivery issues after scroll view
    /// interactions, where NSScrollView can swallow mouseUp from subviews.
    /// Double-click fires onDoubleClick instead of onSelect.
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }

        if event.clickCount == 2 {
            onDoubleClick?(index)
        } else {
            let isCommand = event.modifierFlags.contains(.command)
            onSelect?(index, isCommand)
        }
    }

    @objc private func closeClicked() {
        onClose?(index)
    }
}
