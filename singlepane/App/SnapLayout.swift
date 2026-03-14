// SnapLayout.swift
// Defines the 7 preset layout configurations for snap-to-layout.
// Each preset is a set of visible panels — collapsed panels are the complement.

import Foundation

/// A preset layout that defines which panels are visible.
/// All visible panels share equal width. Hidden panels are collapsed.
enum SnapLayout: String, CaseIterable, Sendable {

    case allEqual = "allEqual"
    case terminalOnly = "terminalOnly"
    case explorerOnly = "explorerOnly"
    case previewOnly = "previewOnly"
    case terminalExplorer = "terminalExplorer"
    case terminalPreview = "terminalPreview"
    case explorerPreview = "explorerPreview"

    /// The set of panels that should be visible in this layout.
    var visiblePanels: Set<PanelType> {
        switch self {
        case .allEqual:          return [.terminal, .explorer, .preview]
        case .terminalOnly:      return [.terminal]
        case .explorerOnly:      return [.explorer]
        case .previewOnly:       return [.preview]
        case .terminalExplorer:  return [.terminal, .explorer]
        case .terminalPreview:   return [.terminal, .preview]
        case .explorerPreview:   return [.explorer, .preview]
        }
    }

    /// Human-readable name for tooltip display.
    var displayName: String {
        switch self {
        case .allEqual:          return "All Panels"
        case .terminalOnly:      return "Terminal Only"
        case .explorerOnly:      return "Files Only"
        case .previewOnly:       return "Editor Only"
        case .terminalExplorer:  return "Terminal + Files"
        case .terminalPreview:   return "Terminal + Editor"
        case .explorerPreview:   return "Files + Editor"
        }
    }
}
