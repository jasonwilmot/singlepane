// ActiveLayoutIconView.swift
// Single clickable icon that shows the currently active layout preset.
// Draws the same 3-column icon as LayoutIconView, plus a small ▾ chevron
// indicating that a dropdown popover is available. Replaces the full strip
// of layout icons in the toolbar to save horizontal space.

import AppKit

// MARK: - Active Layout State

/// Identifies the currently active layout — either a built-in preset or a saved custom.
enum ActiveLayoutState: Equatable {
    case preset(SnapLayout)
    case custom(CustomLayout)

    /// Visible panels for this layout state.
    var visiblePanels: Set<PanelType> {
        switch self {
        case .preset(let snap):   return snap.visiblePanels
        case .custom(let custom):
            return Set(custom.panelVisibility.filter(\.value).map(\.key))
        }
    }

    /// Column order used for icon drawing.
    /// Presets use the global column order; custom layouts use their saved order.
    func columnOrder(global: [PanelType]) -> [PanelType] {
        switch self {
        case .preset:             return global
        case .custom(let custom): return custom.columnOrder
        }
    }

    /// Panel visibility dictionary for custom layouts (nil for presets).
    var customVisibility: [PanelType: Bool]? {
        switch self {
        case .preset:             return nil
        case .custom(let custom): return custom.panelVisibility
        }
    }

    static func == (lhs: ActiveLayoutState, rhs: ActiveLayoutState) -> Bool {
        switch (lhs, rhs) {
        case (.preset(let a), .preset(let b)):
            return a == b
        case (.custom(let a), .custom(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

// MARK: - ActiveLayoutIconView

@MainActor
final class ActiveLayoutIconView: NSView {

    // MARK: - Properties

    /// Current layout state to render.
    var layoutState: ActiveLayoutState = .preset(.allEqual) {
        didSet { needsDisplay = true }
    }

    /// Current global column order (updated on panel reorder).
    var columnOrder: [PanelType] = LayoutConfiguration.default.columnOrder {
        didSet { needsDisplay = true }
    }

    /// Called when the user clicks this icon.
    var onClick: (() -> Void)?

    // MARK: - Drawing Constants

    /// Total width: icon (30) + spacing (4) + chevron area (8).
    private static let totalWidth: CGFloat = 42
    private static let iconWidth: CGFloat = 30
    private static let iconHeight: CGFloat = 18
    private static let columnSpacing: CGFloat = 2
    private static let cornerRadius: CGFloat = 2
    private static let borderInset: CGFloat = 1.5

    // MARK: - Init

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.totalWidth, height: Self.iconHeight))
        toolTip = "Layout Manager"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.totalWidth, height: Self.iconHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let effectiveOrder = layoutState.columnOrder(global: columnOrder)
        let columns = effectiveOrder.count
        guard columns > 0 else { return }

        let theme = ThemeManager.shared.activeTheme

        // -- Icon area (left portion) --

        let iconRect = NSRect(x: 0, y: 0, width: Self.iconWidth, height: bounds.height)

        // Outer border with accent color (always selected since it's the active layout)
        let outerRect = iconRect.insetBy(dx: 0.5, dy: 0.5)
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: Self.cornerRadius + 1,
            yRadius: Self.cornerRadius + 1
        )
        theme.chromeAccent.setStroke()
        outerPath.lineWidth = 1.5
        outerPath.stroke()

        // Inner column rectangles
        let inset = Self.borderInset
        let innerRect = iconRect.insetBy(dx: inset + 1, dy: inset + 1)
        let totalSpacing = Self.columnSpacing * CGFloat(columns - 1)
        let availableWidth = innerRect.width - totalSpacing
        let columnWidth = availableWidth / CGFloat(columns)

        let visiblePanels = layoutState.visiblePanels

        for (index, panelType) in effectiveOrder.enumerated() {
            let x = innerRect.minX + CGFloat(index) * (columnWidth + Self.columnSpacing)
            let rect = NSRect(x: x, y: innerRect.minY, width: columnWidth, height: innerRect.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)

            if visiblePanels.contains(panelType) {
                theme.chromeAccent.withAlphaComponent(0.7).setFill()
            } else {
                theme.chromeTextSecondary.withAlphaComponent(0.15).setFill()
            }
            path.fill()
        }

        // -- Chevron (right portion) --

        let chevronX = Self.iconWidth + 4
        let chevronY = bounds.midY
        let chevronSize: CGFloat = 3

        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: chevronX, y: chevronY + chevronSize))
        chevron.line(to: NSPoint(x: chevronX + chevronSize, y: chevronY - chevronSize + 1))
        chevron.line(to: NSPoint(x: chevronX + chevronSize * 2, y: chevronY + chevronSize))
        theme.chromeTextSecondary.setStroke()
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
