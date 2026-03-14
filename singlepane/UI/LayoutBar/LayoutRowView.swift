// LayoutRowView.swift
// A single row in the Layout Manager popover's layout grid.
// Shows: layout icon | display name | hotkey toggle | optional delete (x) button.
// Reused for both preset SnapLayout and custom layout entries.
// Click on the icon/name area selects the layout; hotkey and delete are independent actions.

import AppKit

@MainActor
final class LayoutRowView: NSView {

    // MARK: - Properties

    /// The layout identifier (SnapLayout.rawValue or CustomLayout UUID string).
    private let layoutID: String

    /// Whether this row represents the currently active layout.
    private let isActive: Bool

    /// Whether this row can be deleted (custom layouts only).
    private let isDeletable: Bool

    /// Called when the user clicks the layout icon/name to select it.
    var onSelect: (() -> Void)?

    /// Called when the user clicks the delete (x) icon.
    var onDelete: (() -> Void)?

    /// Called when a hotkey is recorded or cleared.
    var onHotkeyChanged: (() -> Void)?

    // MARK: - UI Elements

    private let iconView: MiniLayoutIconView
    private let nameLabel = NSTextField(labelWithString: "")
    private let hotkeyToggle: HotkeyToggleView
    private var deleteButton: NSButton?

    // MARK: - Constants

    private static let rowHeight: CGFloat = 26
    private static let iconSize: CGFloat = 22
    private static let deleteButtonSize: CGFloat = 16

    // MARK: - Init

    /// Creates a layout row.
    /// - Parameters:
    ///   - layoutID: Unique identifier (SnapLayout rawValue or CustomLayout UUID).
    ///   - columnOrder: Panel order for drawing the icon.
    ///   - visiblePanels: Which panels are visible in this layout.
    ///   - displayName: Human-readable name shown next to the icon.
    ///   - isActive: Whether this is the currently active layout.
    ///   - customVisibility: Per-panel visibility dict for custom layouts (nil for presets).
    ///   - badgeNumber: Optional badge number for custom layouts.
    ///   - isDeletable: Whether a delete button should be shown.
    init(
        layoutID: String,
        columnOrder: [PanelType],
        visiblePanels: Set<PanelType>,
        displayName: String,
        isActive: Bool,
        customVisibility: [PanelType: Bool]? = nil,
        badgeNumber: Int? = nil,
        isDeletable: Bool = false
    ) {
        self.layoutID = layoutID
        self.isActive = isActive
        self.isDeletable = isDeletable
        self.iconView = MiniLayoutIconView(
            columnOrder: columnOrder,
            visiblePanels: visiblePanels,
            customVisibility: customVisibility,
            badgeNumber: badgeNumber,
            isActive: isActive
        )
        self.hotkeyToggle = HotkeyToggleView(layoutID: layoutID)
        super.init(frame: .zero)

        setupViews(displayName: displayName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews(displayName: String) {
        let theme = ThemeManager.shared.activeTheme

        // Layout icon
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Name label
        nameLabel.stringValue = displayName
        nameLabel.font = FontManager.shared.activeFont.withSize(11)
        nameLabel.textColor = isActive ? theme.chromeAccent : theme.chromeText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Hotkey toggle
        hotkeyToggle.translatesAutoresizingMaskIntoConstraints = false
        hotkeyToggle.onHotkeyChanged = { [weak self] in
            self?.onHotkeyChanged?()
        }

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(hotkeyToggle)

        var constraints = [
            heightAnchor.constraint(equalToConstant: Self.rowHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ]

        if isDeletable {
            let btn = makeDeleteButton()
            addSubview(btn)
            deleteButton = btn

            constraints.append(contentsOf: [
                hotkeyToggle.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -4),
                hotkeyToggle.centerYAnchor.constraint(equalTo: centerYAnchor),

                btn.trailingAnchor.constraint(equalTo: trailingAnchor),
                btn.centerYAnchor.constraint(equalTo: centerYAnchor),
                btn.widthAnchor.constraint(equalToConstant: Self.deleteButtonSize),
                btn.heightAnchor.constraint(equalToConstant: Self.deleteButtonSize),

                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: hotkeyToggle.leadingAnchor, constant: -4),
            ])
        } else {
            constraints.append(contentsOf: [
                hotkeyToggle.trailingAnchor.constraint(equalTo: trailingAnchor),
                hotkeyToggle.centerYAnchor.constraint(equalTo: centerYAnchor),

                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: hotkeyToggle.leadingAnchor, constant: -4),
            ])
        }

        NSLayoutConstraint.activate(constraints)

        // Clickable area for selection (icon + name)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    // MARK: - Delete Button

    private func makeDeleteButton() -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Delete layout"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        btn.contentTintColor = ThemeManager.shared.activeTheme.chromeTextSecondary
        btn.target = self
        btn.action = #selector(deleteClicked)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    @objc private func deleteClicked() {
        onDelete?()
    }

    // MARK: - Mouse Handling (Selection Area)

    override func mouseDown(with event: NSEvent) {
        // Check if click is in the icon/name area (not the hotkey toggle or delete button)
        let point = convert(event.locationInWindow, from: nil)
        let hotkeyFrame = hotkeyToggle.frame
        let deleteFrame = deleteButton?.frame ?? .zero

        if !hotkeyFrame.contains(point) && !deleteFrame.contains(point) {
            onSelect?()
        }
    }

    private var isMouseInside = false

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isMouseInside {
            ThemeManager.shared.activeTheme.chromeText.withAlphaComponent(0.05).setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Updates

    /// Updates the icon's column order and visible panels (after panel reorder).
    func updateColumnOrder(_ newOrder: [PanelType], visiblePanels: Set<PanelType>) {
        iconView.updateColumnOrder(newOrder, visiblePanels: visiblePanels)
    }

    /// Refreshes the hotkey toggle display (after another row records a hotkey).
    func refreshHotkey() {
        hotkeyToggle.needsDisplay = true
    }
}

// MARK: - MiniLayoutIconView

/// Compact layout icon drawn inline within a LayoutRowView.
/// Same visual language as LayoutIconView but smaller and without mouse handling.
@MainActor
final class MiniLayoutIconView: NSView {

    // MARK: - Properties

    private var columnOrder: [PanelType]
    private var visiblePanels: Set<PanelType>
    private let customVisibility: [PanelType: Bool]?
    private let badgeNumber: Int?
    private let isActive: Bool

    // MARK: - Drawing Constants

    private static let columnSpacing: CGFloat = 2
    private static let cornerRadius: CGFloat = 2
    private static let borderInset: CGFloat = 1.5
    private static let badgeSize: CGFloat = 9

    // MARK: - Init

    init(
        columnOrder: [PanelType],
        visiblePanels: Set<PanelType>,
        customVisibility: [PanelType: Bool]?,
        badgeNumber: Int?,
        isActive: Bool
    ) {
        self.columnOrder = columnOrder
        self.visiblePanels = visiblePanels
        self.customVisibility = customVisibility
        self.badgeNumber = badgeNumber
        self.isActive = isActive
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 18))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let columns = columnOrder.count
        guard columns > 0 else { return }

        let theme = ThemeManager.shared.activeTheme
        let inset = Self.borderInset

        // Outer border
        let outerRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: Self.cornerRadius + 1,
            yRadius: Self.cornerRadius + 1
        )

        if isActive {
            theme.chromeAccent.setStroke()
            outerPath.lineWidth = 1.5
        } else {
            theme.chromeBorder.setStroke()
            outerPath.lineWidth = 1
        }
        outerPath.stroke()

        // Inner column rectangles
        let innerRect = bounds.insetBy(dx: inset + 1, dy: inset + 1)
        let totalSpacing = Self.columnSpacing * CGFloat(columns - 1)
        let availableWidth = innerRect.width - totalSpacing
        let columnWidth = availableWidth / CGFloat(columns)

        for (index, panelType) in columnOrder.enumerated() {
            let x = innerRect.minX + CGFloat(index) * (columnWidth + Self.columnSpacing)
            let rect = NSRect(x: x, y: innerRect.minY, width: columnWidth, height: innerRect.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)

            let isVisible: Bool
            if let custom = customVisibility {
                isVisible = custom[panelType] ?? true
            } else {
                isVisible = visiblePanels.contains(panelType)
            }

            if isVisible {
                theme.chromeAccent.withAlphaComponent(0.7).setFill()
            } else {
                theme.chromeTextSecondary.withAlphaComponent(0.15).setFill()
            }
            path.fill()
        }

        // Badge for custom layouts
        if let number = badgeNumber {
            drawBadge(number: number)
        }
    }

    /// Draws a numbered circle badge at the bottom-right of the icon.
    private func drawBadge(number: Int) {
        let size = Self.badgeSize
        let badgeRect = NSRect(
            x: bounds.maxX - size - 1,
            y: bounds.minY + 1,
            width: size,
            height: size
        )

        let theme = ThemeManager.shared.activeTheme
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        theme.chromeAccent.setFill()
        badgePath.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6, weight: .bold),
            .foregroundColor: theme.chromeBackground,
        ]
        let str = NSAttributedString(string: "\(number)", attributes: attrs)
        let textSize = str.size()
        str.draw(at: NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        ))
    }

    // MARK: - Updates

    /// Updates the column order and visible panels for a fresh redraw.
    func updateColumnOrder(_ newOrder: [PanelType], visiblePanels: Set<PanelType>) {
        self.columnOrder = newOrder
        self.visiblePanels = visiblePanels
        needsDisplay = true
    }
}
