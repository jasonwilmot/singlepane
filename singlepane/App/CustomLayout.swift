// CustomLayout.swift
// Data model for user-saved custom layout presets.
// Captures column order, panel visibility, width ratios, and inner split ratios.
// Codable for UserDefaults persistence via JSONEncoder/JSONDecoder.

import Foundation

/// A user-saved layout preset that captures the full workspace state.
struct CustomLayout: Codable, Identifiable, Sendable {

    /// Unique identifier for this layout.
    let id: UUID

    /// Ordered list of panels from left to right at time of save.
    var columnOrder: [PanelType]

    /// Per-panel visibility at time of save.
    var panelVisibility: [PanelType: Bool]

    /// Per-panel relative width (0–1, sums to 1 across visible panels).
    var panelWidthRatios: [PanelType: CGFloat]

    /// Per-panel inner split ratio (e.g. explorer top/bottom pane split).
    /// Key present only for panels that have an inner split.
    var innerSplitRatios: [PanelType: CGFloat]

    /// Timestamp of creation.
    let createdAt: Date
}
