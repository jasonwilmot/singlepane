// ViewMode.swift
// Defines the available file panel view modes and thumbnail size tiers.
// Only list and thumbnail are implemented initially; others are placeholders
// for column and brief modes (tickets #58, #60).

import Foundation

/// View modes available in a file panel. Each tab persists its own view mode.
enum ViewMode: String, CaseIterable, Sendable {
    case list
    case thumbnail
    case column
    case brief

    /// SF Symbol name representing this view mode.
    var symbolName: String {
        switch self {
        case .list:      return "list.bullet"
        case .thumbnail: return "square.grid.2x2"
        case .column:    return "rectangle.split.3x1"
        case .brief:     return "rectangle.split.1x2"
        }
    }

    /// Cycles to the next implemented view mode.
    /// Order: list → thumbnail → brief → list. Column is not yet implemented.
    var next: ViewMode {
        switch self {
        case .list:      return .thumbnail
        case .thumbnail: return .brief
        case .brief:     return .list
        // Column mode cycles back to list until implemented
        case .column:    return .list
        }
    }
}

/// Discrete thumbnail size tiers. Global setting shared across all tabs.
enum ThumbnailSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// Pixel dimension for the thumbnail cell (width and height).
    var pointSize: CGFloat {
        switch self {
        case .small:  return 64
        case .medium: return 128
        case .large:  return 256
        }
    }

    /// SF Symbol name hint for the size indicator.
    var symbolName: String {
        switch self {
        case .small:  return "s.circle"
        case .medium: return "m.circle"
        case .large:  return "l.circle"
        }
    }

    /// Cycles to the next size tier (small → medium → large → small).
    var next: ThumbnailSize {
        switch self {
        case .small:  return .medium
        case .medium: return .large
        case .large:  return .small
        }
    }
}

/// Manages persistence of view mode (per-tab) and thumbnail size (global).
enum ViewModeStore {

    private static let sizeKey = "globalThumbnailSize"

    /// Persists the view mode for a specific tab identifier.
    static func save(viewMode: ViewMode, forTab tabID: String) {
        UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode_\(tabID)")
    }

    /// Loads the persisted view mode for a tab, defaulting to `.list`.
    static func loadViewMode(forTab tabID: String) -> ViewMode {
        guard let raw = UserDefaults.standard.string(forKey: "viewMode_\(tabID)"),
              let mode = ViewMode(rawValue: raw) else { return .list }
        return mode
    }

    /// Persists the global thumbnail size.
    static func save(thumbnailSize: ThumbnailSize) {
        UserDefaults.standard.set(thumbnailSize.rawValue, forKey: sizeKey)
    }

    /// Loads the persisted thumbnail size, defaulting to `.medium`.
    static func loadThumbnailSize() -> ThumbnailSize {
        guard let raw = UserDefaults.standard.string(forKey: sizeKey),
              let size = ThumbnailSize(rawValue: raw) else { return .medium }
        return size
    }
}
