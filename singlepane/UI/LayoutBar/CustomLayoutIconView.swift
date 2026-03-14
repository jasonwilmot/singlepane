// CustomLayoutIconView.swift
// Custom-drawn button representing a user-saved layout preset.
// Same visual style as LayoutIconView but with a number badge overlay.
// Supports right-click context menu for deletion and hotkey assignment.
// Solid outer border if a hotkey is assigned; dashed if not.

import AppKit

@MainActor
final class CustomLayoutIconView: NSView {

    // MARK: - Properties

    /// The saved custom layout this icon represents.
    let customLayout: CustomLayout

    /// Sequential display number (1-based, renumbered on delete).
    let displayNumber: Int

    /// Whether this layout is currently active (draws highlight).
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    /// Called when the user clicks this icon.
    var onSelect: ((CustomLayout) -> Void)?

    /// Called when the user right-clicks and selects "Delete".
    var onDelete: (() -> Void)?

    /// Column order from the saved layout (used for drawing rectangles).
    private let columnOrder: [PanelType]

    /// Popover shown for hotkey recording.
    private var hotkeyPopover: NSPopover?

    // MARK: - Drawing Constants

    private static let iconWidth: CGFloat = 30
    private static let iconHeight: CGFloat = 18
    private static let columnSpacing: CGFloat = 2
    private static let cornerRadius: CGFloat = 2
    private static let borderInset: CGFloat = 1.5
    private static let badgeSize: CGFloat = 9

    /// Dash pattern for icons without a hotkey: [dash length, gap length].
    private static let dashPattern: [CGFloat] = [3, 2]

    // MARK: - Init

    init(customLayout: CustomLayout, displayNumber: Int, columnOrder: [PanelType]) {
        self.customLayout = customLayout
        self.displayNumber = displayNumber
        self.columnOrder = columnOrder
        super.init(frame: NSRect(x: 0, y: 0, width: Self.iconWidth, height: Self.iconHeight))
        toolTip = "Custom \(displayNumber)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.iconWidth, height: Self.iconHeight)
    }

    // MARK: - Hotkey State

    /// The layout identifier used for hotkey lookups (UUID string).
    private var layoutID: String {
        customLayout.id.uuidString
    }

    /// Whether this layout has a hotkey assigned.
    private var hasHotkey: Bool {
        LayoutHotkeyManager.shared.hasHotkey(for: layoutID)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let columns = columnOrder.count
        guard columns > 0 else { return }

        let inset = Self.borderInset

        // Outer border
        let outerRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: Self.cornerRadius + 1,
            yRadius: Self.cornerRadius + 1
        )

        if isSelected {
            ThemeManager.shared.activeTheme.chromeAccent.setStroke()
            outerPath.lineWidth = 1.5
        } else {
            borderColor.setStroke()
            outerPath.lineWidth = 1
        }

        // Dashed border when no hotkey is assigned
        if !hasHotkey {
            outerPath.setLineDash(Self.dashPattern, count: Self.dashPattern.count, phase: 0)
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

            let isVisible = customLayout.panelVisibility[panelType] ?? true
            if isVisible {
                filledColor.setFill()
                path.fill()
            } else {
                emptyColor.setFill()
                path.fill()
            }
        }

        // Number badge — bottom-right corner
        drawBadge()
    }

    /// Draws a small numbered circle badge at the bottom-right of the icon.
    private func drawBadge() {
        let size = Self.badgeSize
        let badgeRect = NSRect(
            x: bounds.maxX - size - 1,
            y: bounds.minY + 1,
            width: size,
            height: size
        )

        // Badge background
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        ThemeManager.shared.activeTheme.chromeAccent.setFill()
        badgePath.fill()

        // Badge number
        let numberString = "\(displayNumber)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6, weight: .bold),
            .foregroundColor: ThemeManager.shared.activeTheme.chromeBackground,
        ]
        let attrString = NSAttributedString(string: numberString, attributes: attributes)
        let textSize = attrString.size()
        let textOrigin = NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        )
        attrString.draw(at: textOrigin)
    }

    // MARK: - Colors (theme-driven)

    private var filledColor: NSColor {
        ThemeManager.shared.activeTheme.chromeAccent.withAlphaComponent(0.7)
    }

    private var emptyColor: NSColor {
        ThemeManager.shared.activeTheme.chromeTextSecondary.withAlphaComponent(0.15)
    }

    private var borderColor: NSColor {
        ThemeManager.shared.activeTheme.chromeBorder
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        onSelect?(customLayout)
    }

    /// Right-click opens the hotkey popover directly, with a "Delete Layout" button inside.
    override func rightMouseDown(with event: NSEvent) {
        showHotkeyPopover()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Hotkey Popover

    /// Creates and shows the hotkey recorder popover anchored to this icon.
    /// Includes a "Delete Layout" button at the bottom for custom layout removal.
    private func showHotkeyPopover() {
        let popover = NSPopover()
        let recorder = HotkeyRecorderPopoverViewController(layoutID: layoutID)
        recorder.onHotkeyChanged = { [weak self] in
            self?.needsDisplay = true
        }
        recorder.onDeleteLayout = { [weak self, weak popover] in
            popover?.close()
            self?.onDelete?()
        }
        popover.contentViewController = recorder
        popover.behavior = .transient
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        hotkeyPopover = popover
    }
}
