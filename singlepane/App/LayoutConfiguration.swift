// LayoutConfiguration.swift
// Data-driven layout model. Defines column order, terminal tab orientation,
// and panel visibility. Column arrangement reads from this — not hardcoded.

import Foundation

// MARK: - Panel Type

/// Identifies each column panel by its role.
enum PanelType: String, Codable, Sendable {
    case terminal
    case explorer
    case preview

    /// Human-readable name for tooltips and UI labels.
    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .explorer: return "Explorer"
        case .preview:  return "Preview"
        }
    }
}

// MARK: - Shift Direction

/// Direction for swapping a panel with its neighbor.
enum PanelShiftDirection: Sendable {
    case left
    case right
}

// MARK: - Panel Shift Delegate

/// Adopted by the root split controller to handle panel reorder requests.
/// Panels call `shiftPanel(_:direction:)` when the user clicks a shift arrow.
@MainActor
protocol PanelShiftDelegate: AnyObject {
    func shiftPanel(_ panel: PanelType, direction: PanelShiftDirection)
}

// MARK: - Shift Arrow State

/// Describes which shift arrows a panel should show and their tooltips.
struct ShiftArrowState: Sendable {
    let showLeft: Bool
    let showRight: Bool
    let leftTooltip: String?
    let rightTooltip: String?

    /// No arrows visible — used for hidden panels or single-panel layouts.
    static let hidden = ShiftArrowState(showLeft: false, showRight: false,
                                        leftTooltip: nil, rightTooltip: nil)
}

// MARK: - Tab Orientation

/// Terminal tab bar placement direction.
enum TabOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

// MARK: - Arrangement Mode

/// Controls how multiple terminal panes are arranged within the terminal panel.
/// Cycles: vertical (columns) → horizontal (rows) → grid (2D auto-layout).
enum ArrangementMode: String, Codable, Sendable {
    case vertical
    case horizontal
    case grid

    /// UserDefaults key for persisting the selected arrangement mode across sessions.
    static let defaultsKey = "terminalArrangementMode"

    /// SF Symbol name representing this arrangement mode.
    var symbolName: String {
        switch self {
        case .vertical:   return "rectangle.split.1x2"
        case .horizontal: return "rectangle.split.2x1"
        case .grid:       return "rectangle.split.2x2"
        }
    }

    /// The next mode in the cycle. Pass the current panel count to skip
    /// grid when ≤2 panels (grid would be indistinguishable from vertical).
    func next(panelCount: Int) -> ArrangementMode {
        switch self {
        case .vertical:   return .horizontal
        case .horizontal: return panelCount > 2 ? .grid : .vertical
        case .grid:       return .vertical
        }
    }

    /// Computes the grid dimensions for a given panel count.
    /// Returns (columns, rows) using `cols = ceil(sqrt(n))`, `rows = ceil(n / cols)`.
    static func gridDimensions(for count: Int) -> (cols: Int, rows: Int) {
        guard count > 0 else { return (0, 0) }
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        return (cols, rows)
    }
}

// MARK: - Layout Configuration

/// Defines the workspace layout. Codable for future persistence.
struct LayoutConfiguration: Codable, Sendable {

    /// Ordered list of panels from left to right.
    var columnOrder: [PanelType]

    /// Terminal tab bar orientation (horizontal or vertical).
    var terminalTabOrientation: TabOrientation

    /// Per-panel visibility. Panels not in this dictionary default to visible.
    var panelVisibility: [PanelType: Bool]

    /// Default layout: Terminal | Explorer | Preview, horizontal tabs.
    static let `default` = LayoutConfiguration(
        columnOrder: [.terminal, .explorer, .preview],
        terminalTabOrientation: .horizontal,
        panelVisibility: [
            .terminal: true,
            .explorer: true,
            .preview: true
        ]
    )

    /// Check whether a panel is visible.
    func isVisible(_ panel: PanelType) -> Bool {
        panelVisibility[panel] ?? true
    }

    // MARK: - Terminal Tab Orientation Persistence

    /// UserDefaults key for persisting the terminal tab orientation across sessions.
    private static let tabOrientationKey = "terminalTabOrientation"

    /// Saves the terminal tab orientation to UserDefaults.
    static func saveTerminalTabOrientation(_ orientation: TabOrientation) {
        UserDefaults.standard.set(orientation.rawValue, forKey: tabOrientationKey)
    }

    /// Loads the saved terminal tab orientation from UserDefaults, falling back to `.horizontal`.
    static func loadTerminalTabOrientation() -> TabOrientation {
        guard let raw = UserDefaults.standard.string(forKey: tabOrientationKey),
              let orientation = TabOrientation(rawValue: raw) else {
            return Self.default.terminalTabOrientation
        }
        return orientation
    }

    // MARK: - Column Order Persistence

    /// UserDefaults key for persisting the column order across sessions.
    private static let columnOrderKey = "savedColumnOrder"

    /// Saves the current column order to UserDefaults.
    static func saveColumnOrder(_ order: [PanelType]) {
        let rawValues = order.map(\.rawValue)
        UserDefaults.standard.set(rawValues, forKey: columnOrderKey)
    }

    /// Loads the saved column order from UserDefaults, falling back to the default.
    static func loadColumnOrder() -> [PanelType] {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: columnOrderKey) else {
            return Self.default.columnOrder
        }
        let panels = rawValues.compactMap(PanelType.init(rawValue:))
        // Validate that all three panel types are present
        guard panels.count == Self.default.columnOrder.count,
              Set(panels) == Set(Self.default.columnOrder) else {
            return Self.default.columnOrder
        }
        return panels
    }
}
