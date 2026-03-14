// BreadcrumbSegmentView.swift
// A single clickable breadcrumb segment with optional dropdown arrow.
// Supports normal (full opacity) and ghost (reduced opacity) display modes.
// Used by BreadcrumbBarView to compose the full breadcrumb path bar.

import AppKit

/// Actions emitted by a breadcrumb segment.
@MainActor
protocol BreadcrumbSegmentDelegate: AnyObject {
    /// The segment label was clicked — navigate to its path.
    func breadcrumbSegmentClicked(url: URL)
    /// The dropdown arrow was clicked — show sibling directories.
    func breadcrumbSegmentDropdownRequested(segment: BreadcrumbSegmentView, at url: URL)
}

@MainActor
final class BreadcrumbSegmentView: NSView {

    // MARK: - Configuration

    /// The directory URL this segment represents.
    let url: URL

    /// Whether this segment is a ghost (faded, previously visited deeper path).
    let isGhost: Bool

    /// Opacity applied to ghost segments.
    private static let ghostOpacity: CGFloat = 0.4

    weak var delegate: BreadcrumbSegmentDelegate?

    // MARK: - Subviews

    private let label = NSTextField(labelWithString: "")
    private let dropdownArrow = NSButton()

    // MARK: - Init

    init(title: String, url: URL, isGhost: Bool = false) {
        self.url = url
        self.isGhost = isGhost
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews(title: title)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupSubviews(title: String) {
        let font = FontManager.shared.activeFont.withSize(12)
        let opacity: CGFloat = isGhost ? Self.ghostOpacity : 1.0

        // Label — clickable segment name
        label.stringValue = title
        label.font = font
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.alphaValue = opacity
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Dropdown arrow — small down chevron, doubles as visual separator
        dropdownArrow.bezelStyle = .inline
        dropdownArrow.isBordered = false
        dropdownArrow.title = ""
        dropdownArrow.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: "Show sibling folders"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        )
        dropdownArrow.imagePosition = .imageOnly
        dropdownArrow.target = self
        dropdownArrow.action = #selector(dropdownClicked(_:))
        dropdownArrow.alphaValue = opacity * 0.7
        dropdownArrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dropdownArrow)

        // Layout: [label][dropdown arrow]
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            dropdownArrow.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 1),
            dropdownArrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            dropdownArrow.widthAnchor.constraint(equalToConstant: 14),
            dropdownArrow.heightAnchor.constraint(equalToConstant: 14),
            dropdownArrow.trailingAnchor.constraint(equalTo: trailingAnchor),

            heightAnchor.constraint(equalToConstant: 20),
        ])

        // Click gesture on label
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(labelClicked(_:)))
        label.addGestureRecognizer(clickGesture)
    }

    // MARK: - Theme

    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        label.textColor = theme.chromeText
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

    @objc private func labelClicked(_ sender: Any) {
        delegate?.breadcrumbSegmentClicked(url: url)
    }

    @objc private func dropdownClicked(_ sender: NSButton) {
        delegate?.breadcrumbSegmentDropdownRequested(segment: self, at: url)
    }
}
