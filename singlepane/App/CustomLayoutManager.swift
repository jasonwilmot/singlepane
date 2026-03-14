// CustomLayoutManager.swift
// Singleton that manages user-saved custom layout presets.
// Persists to UserDefaults via JSONEncoder/JSONDecoder.
// Mirrors the ThemeManager/FontManager pattern.

import Foundation

@MainActor
@Observable
final class CustomLayoutManager {

    // MARK: - Singleton

    static let shared = CustomLayoutManager()

    // MARK: - State

    /// All saved custom layouts, ordered by creation time.
    private(set) var customLayouts: [CustomLayout] = []

    // MARK: - Constants

    /// Maximum number of custom layouts a user can save.
    static let maxLayouts = 5

    // MARK: - UserDefaults Key

    private static let storageKey = "customLayouts"

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Save

    /// Saves a new custom layout. Returns false if at capacity.
    @discardableResult
    func save(layout: CustomLayout) -> Bool {
        guard customLayouts.count < Self.maxLayouts else { return false }
        customLayouts.append(layout)
        persist()
        return true
    }

    // MARK: - Delete

    /// Deletes the custom layout at the given index.
    func delete(at index: Int) {
        guard customLayouts.indices.contains(index) else { return }
        customLayouts.remove(at: index)
        persist()
    }

    /// Whether a new custom layout can be saved.
    var canSave: Bool {
        customLayouts.count < Self.maxLayouts
    }

    // MARK: - Persistence

    /// Loads saved layouts from UserDefaults.
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let layouts = try? JSONDecoder().decode([CustomLayout].self, from: data) else {
            return
        }
        customLayouts = layouts
    }

    /// Persists current layouts to UserDefaults.
    private func persist() {
        guard let data = try? JSONEncoder().encode(customLayouts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
