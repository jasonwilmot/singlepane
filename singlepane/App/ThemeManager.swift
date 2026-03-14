// ThemeManager.swift
// Global theme state — loads bundled presets, persists selection, notifies observers.
// All views read colors from ThemeManager.shared.activeTheme.

import AppKit

@MainActor
@Observable
final class ThemeManager {

    // MARK: - Singleton

    static let shared = ThemeManager()

    // MARK: - State

    /// The currently active theme applied across all UI.
    private(set) var activeTheme: Theme

    /// All available themes (bundled presets).
    let availableThemes: [Theme]

    // MARK: - UserDefaults Key

    private static let selectedThemeKey = "selectedThemeName"
    private static let defaultThemeName = "Catppuccin Mocha"

    // MARK: - Init

    private init() {
        let themes = Self.loadBundledThemes()
        self.availableThemes = themes

        // Restore persisted selection, or fall back to default
        let savedName = UserDefaults.standard.string(forKey: Self.selectedThemeKey)
            ?? Self.defaultThemeName
        self.activeTheme = themes.first(where: { $0.name == savedName })
            ?? themes.first
            ?? Self.fallbackTheme
    }

    // MARK: - Theme Selection

    /// Switch to a theme by name. Persists the selection.
    func selectTheme(named name: String) {
        guard let theme = availableThemes.first(where: { $0.name == name }) else { return }
        activeTheme = theme
        UserDefaults.standard.set(name, forKey: Self.selectedThemeKey)
    }

    // MARK: - Bundle Loading

    /// Theme file names (without extension) matching the JSON files in the bundle.
    private static let themeFileNames = [
        "ayu-dark", "catppuccin-frappe", "catppuccin-mocha",
        "cyberdream", "dracula", "everforest-dark",
        "gruvbox-dark", "kanagawa", "moonfly",
        "nightfox", "nord", "one-dark",
        "rose-pine", "solarized-dark",
        "tokyo-night", "vesper"
    ]

    /// Loads all bundled theme JSON files from the app resources.
    private static func loadBundledThemes() -> [Theme] {
        let decoder = JSONDecoder()
        var themes: [Theme] = []

        for fileName in themeFileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let theme = try? decoder.decode(Theme.self, from: data) else {
                NSLog("ThemeManager: Failed to load theme '\(fileName).json'")
                continue
            }
            themes.append(theme)
        }

        // Sort alphabetically, but put Catppuccin Mocha first as default
        themes.sort { a, b in
            if a.name == defaultThemeName { return true }
            if b.name == defaultThemeName { return false }
            return a.name < b.name
        }

        return themes.isEmpty ? [fallbackTheme] : themes
    }

    // MARK: - Fallback

    /// Hardcoded fallback if no themes can be loaded (should never happen).
    private static let fallbackTheme = Theme(
        name: "Default",
        foreground: "#CCCCCC",
        background: "#1E1E1E",
        cursor: "#CCCCCC",
        cursorText: "#1E1E1E",
        selectionBackground: "#3A3A3A",
        selectionForeground: "#CCCCCC",
        palette: [
            "#000000", "#CC0000", "#00CC00", "#CCCC00",
            "#0000CC", "#CC00CC", "#00CCCC", "#CCCCCC",
            "#555555", "#FF0000", "#00FF00", "#FFFF00",
            "#5555FF", "#FF00FF", "#00FFFF", "#FFFFFF"
        ]
    )
}
