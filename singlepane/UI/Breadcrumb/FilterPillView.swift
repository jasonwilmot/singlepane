// FilterPillView.swift
// Dismissible pill badge showing the active FAYT filter text.
// Displayed after the last breadcrumb segment when a filter is locked in.
// Clicking the "✕" button clears the filter.

import AppKit

@MainActor
final class FilterPillView: NSView {

    // MARK: - Properties

    /// Called when the user clicks the dismiss button to clear the filter.
    var onDismiss: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()

    // MARK: - Init

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews(text: text)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupSubviews(text: String) {
        wantsLayer = true
        layer?.cornerRadius = 4

        // Filter text label
        label.stringValue = text
        label.font = FontManager.shared.activeFont.withSize(10)
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Dismiss "✕" button
        dismissButton.bezelStyle = .inline
        dismissButton.isBordered = false
        dismissButton.title = ""
        dismissButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Clear filter"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        )
        dismissButton.imagePosition = .imageOnly
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            dismissButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 12),
            dismissButton.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    // MARK: - Theme

    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.2).cgColor
        label.textColor = theme.chromeText
        dismissButton.contentTintColor = theme.chromeTextSecondary
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

    // MARK: - Actions

    @objc private func dismissClicked() {
        onDismiss?()
    }
}
