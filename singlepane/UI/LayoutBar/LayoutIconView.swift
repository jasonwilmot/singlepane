// LayoutIconView.swift
// Custom-drawn button representing a snap layout preset.
// Draws 3 column rectangles — filled for visible panels, empty for collapsed.
// Highlights when this layout is the active selection.
// Solid outer border if a hotkey is assigned; dashed if not.
// Right-click opens a hotkey recorder popover.

import AppKit

@MainActor
final class LayoutIconView: NSView {

    // MARK: - Properties

    /// The layout this icon represents.
    let layout: SnapLayout

    /// Whether this layout is currently active (draws highlight).
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    /// Called when the user clicks this icon.
    var onSelect: ((SnapLayout) -> Void)?

    /// Column order used to determine which rectangles are filled.
    private let columnOrder: [PanelType]

    /// Popover shown on right-click for hotkey recording.
    private var hotkeyPopover: NSPopover?

    // MARK: - Drawing Constants

    private static let iconWidth: CGFloat = 30
    private static let iconHeight: CGFloat = 18
    private static let columnSpacing: CGFloat = 2
    private static let cornerRadius: CGFloat = 2
    private static let borderInset: CGFloat = 1.5

    /// Dash pattern for icons without a hotkey: [dash length, gap length].
    private static let dashPattern: [CGFloat] = [3, 2]

    // MARK: - Init

    init(layout: SnapLayout, columnOrder: [PanelType]) {
        self.layout = layout
        self.columnOrder = columnOrder
        super.init(frame: NSRect(x: 0, y: 0, width: Self.iconWidth, height: Self.iconHeight))
        toolTip = layout.displayName
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

    /// Whether this layout has a hotkey assigned.
    private var hasHotkey: Bool {
        LayoutHotkeyManager.shared.hasHotkey(for: layout.rawValue)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let columns = columnOrder.count
        guard columns > 0 else { return }

        let inset = Self.borderInset

        // Outer border around the entire icon for visual grouping
        let outerRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: Self.cornerRadius + 1,
            yRadius: Self.cornerRadius + 1
        )

        if isSelected {
            // Selected: accent color border
            ThemeManager.shared.activeTheme.chromeAccent.setStroke()
            outerPath.lineWidth = 1.5
        } else {
            // Default: subtle border for grouping
            borderColor.setStroke()
            outerPath.lineWidth = 1
        }

        // Dashed border when no hotkey is assigned
        if !hasHotkey {
            outerPath.setLineDash(Self.dashPattern, count: Self.dashPattern.count, phase: 0)
        }

        outerPath.stroke()

        // Inner area for column rectangles
        let innerRect = bounds.insetBy(dx: inset + 1, dy: inset + 1)
        let totalSpacing = Self.columnSpacing * CGFloat(columns - 1)
        let availableWidth = innerRect.width - totalSpacing
        let columnWidth = availableWidth / CGFloat(columns)

        let visiblePanels = layout.visiblePanels

        for (index, panelType) in columnOrder.enumerated() {
            let x = innerRect.minX + CGFloat(index) * (columnWidth + Self.columnSpacing)
            let rect = NSRect(x: x, y: innerRect.minY, width: columnWidth, height: innerRect.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)

            if visiblePanels.contains(panelType) {
                // Filled column — visible panel
                filledColor.setFill()
                path.fill()
            } else {
                // Empty column — collapsed panel
                emptyColor.setFill()
                path.fill()
            }
        }
    }

    // MARK: - Colors (theme-driven)

    /// Filled column color — uses theme accent.
    private var filledColor: NSColor {
        ThemeManager.shared.activeTheme.chromeAccent.withAlphaComponent(0.7)
    }

    /// Empty column background.
    private var emptyColor: NSColor {
        ThemeManager.shared.activeTheme.chromeTextSecondary.withAlphaComponent(0.15)
    }

    /// Outer border for visual grouping.
    private var borderColor: NSColor {
        ThemeManager.shared.activeTheme.chromeBorder
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        onSelect?(layout)
    }

    /// Right-click opens the hotkey recorder popover directly (no context menu for presets).
    override func rightMouseDown(with event: NSEvent) {
        showHotkeyPopover()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Hotkey Popover

    /// Creates and shows the hotkey recorder popover anchored to this icon.
    private func showHotkeyPopover() {
        let popover = NSPopover()
        let recorder = HotkeyRecorderPopoverViewController(layoutID: layout.rawValue)
        recorder.onHotkeyChanged = { [weak self] in
            self?.needsDisplay = true
        }
        popover.contentViewController = recorder
        popover.behavior = .transient
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        hotkeyPopover = popover
    }
}
