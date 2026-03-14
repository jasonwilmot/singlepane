// FontManager.swift
// Global font state — manages the active monospace font for terminal and UI text.
// Offers popular Ghostty community fonts + macOS system monospace fonts.
// Only shows fonts that are actually installed on the user's system.

import AppKit
import CoreText

// MARK: - FontPreset

/// A named font preset with its macOS font family name.
struct FontPreset: Sendable {
    /// Display name shown in the font picker.
    let displayName: String

    /// The macOS font family name used to instantiate the font.
    let fontFamily: String

    /// Bundle resource filename for bundled fonts (e.g. "GeistMono-Regular"), nil for system fonts.
    let bundleResourceName: String?

    /// Bundle resource extension for bundled fonts (e.g. "ttf"), nil for system fonts.
    let bundleResourceExt: String?

    init(displayName: String, fontFamily: String, bundleResource: (name: String, ext: String)? = nil) {
        self.displayName = displayName
        self.fontFamily = fontFamily
        self.bundleResourceName = bundleResource?.name
        self.bundleResourceExt = bundleResource?.ext
    }

    /// Whether this font is available on the current system.
    var isAvailable: Bool {
        NSFont(name: fontFamily, size: 13) != nil
    }
}

// MARK: - FontManager

@MainActor
@Observable
final class FontManager {

    // MARK: - Singleton

    static let shared = FontManager()

    // MARK: - State

    /// The currently active font applied to terminal and UI text.
    private(set) var activeFont: NSFont

    /// The display name of the active font preset.
    private(set) var activeFontName: String

    /// All font presets (filtered to only those installed on this system).
    let availableFonts: [FontPreset]

    // MARK: - UserDefaults Key

    private static let selectedFontKey = "selectedFontName"
    private static let defaultFontName = "System Mono"

    // MARK: - All Presets

    /// Bundled fonts, macOS system fonts, and optional user-installed fonts.
    /// System Mono listed first as the default, then all others alphabetically.
    private static let allPresets: [FontPreset] = [
        // macOS system monospace (always available via monospacedSystemFont)
        FontPreset(displayName: "System Mono", fontFamily: "SF Mono"),

        // All other fonts — alphabetical
        FontPreset(displayName: "Andale Mono", fontFamily: "Andale Mono"),
        FontPreset(displayName: "Berkeley Mono", fontFamily: "BerkeleyMono-Regular"),
        FontPreset(displayName: "Cascadia Code", fontFamily: "CascadiaCode-Regular", bundleResource: ("CascadiaCode-Regular", "ttf")),
        FontPreset(displayName: "Courier New", fontFamily: "Courier New"),
        FontPreset(displayName: "Departure Mono", fontFamily: "DepartureMono-Regular", bundleResource: ("DepartureMono-Regular", "otf")),
        FontPreset(displayName: "Fira Code", fontFamily: "FiraCode-Regular", bundleResource: ("FiraCode-Regular", "ttf")),
        FontPreset(displayName: "Geist Mono", fontFamily: "GeistMono-Regular", bundleResource: ("GeistMono-Regular", "ttf")),
        FontPreset(displayName: "Hack", fontFamily: "Hack-Regular", bundleResource: ("Hack-Regular", "ttf")),
        FontPreset(displayName: "Inconsolata", fontFamily: "Inconsolata-Regular", bundleResource: ("Inconsolata-Regular", "ttf")),
        FontPreset(displayName: "Iosevka", fontFamily: "Iosevka", bundleResource: ("Iosevka-Regular", "ttf")),
        FontPreset(displayName: "JetBrains Mono", fontFamily: "JetBrainsMono-Regular", bundleResource: ("JetBrainsMono-Regular", "ttf")),
        FontPreset(displayName: "Maple Mono", fontFamily: "MapleMono-Regular", bundleResource: ("MapleMono-Regular", "ttf")),
        FontPreset(displayName: "Menlo", fontFamily: "Menlo"),
        FontPreset(displayName: "Monaco", fontFamily: "Monaco"),
        FontPreset(displayName: "PT Mono", fontFamily: "PT Mono"),
        FontPreset(displayName: "Victor Mono", fontFamily: "VictorMono-Regular", bundleResource: ("VictorMono-Regular", "ttf")),
    ]

    // MARK: - Constants

    /// Default terminal font size.
    static let defaultFontSize: CGFloat = 13

    // MARK: - Init

    private init() {
        // Filter to only installed fonts. "System Mono" is always available.
        let available = Self.allPresets.filter { preset in
            preset.displayName == Self.defaultFontName || preset.isAvailable
        }
        self.availableFonts = available

        // Restore persisted selection
        let savedName = UserDefaults.standard.string(forKey: Self.selectedFontKey)
            ?? Self.defaultFontName
        let preset = available.first(where: { $0.displayName == savedName })
            ?? available.first!
        self.activeFontName = preset.displayName
        self.activeFont = Self.makeFont(for: preset)
    }

    // MARK: - Font Selection

    /// Switch to a font by display name. Persists the selection.
    func selectFont(named name: String) {
        guard let preset = availableFonts.first(where: { $0.displayName == name }) else { return }
        activeFontName = preset.displayName
        activeFont = Self.makeFont(for: preset)
        UserDefaults.standard.set(name, forKey: Self.selectedFontKey)
    }

    // MARK: - CSS Font for WKWebView

    /// Returns a CSS `@font-face` declaration and family name for the active font.
    /// Bundled fonts are embedded as base64 data URIs since WKWebView runs in a
    /// separate process and cannot access process-scoped registered fonts.
    /// System fonts return just a CSS-safe family name with no @font-face needed.
    var cssFontFace: (fontFaceRule: String, familyName: String) {
        let preset = availableFonts.first(where: { $0.displayName == activeFontName })
            ?? availableFonts.first!

        // Bundled font — embed via @font-face with base64 data URI
        if let resName = preset.bundleResourceName,
           let resExt = preset.bundleResourceExt,
           let url = Bundle.main.url(forResource: resName, withExtension: resExt),
           let data = try? Data(contentsOf: url) {
            let mime = resExt == "otf" ? "font/otf" : "font/ttf"
            let base64 = data.base64EncodedString()
            let cssName = preset.displayName
            let rule = """
            @font-face {
                font-family: "\(cssName)";
                src: url("data:\(mime);base64,\(base64)") format("\(resExt == "otf" ? "opentype" : "truetype")");
                font-weight: normal;
                font-style: normal;
            }
            """
            return (rule, cssName)
        }

        // System font — use a CSS-safe name
        let cssName: String
        if preset.displayName == Self.defaultFontName {
            cssName = "SF Mono"
        } else {
            cssName = preset.displayName
        }
        return ("", cssName)
    }

    // MARK: - Font Construction

    /// The PostScript name of the bundled Nerd Font symbols font.
    /// Must match the internal name registered via CTFontManagerRegisterFontsForURL in AppDelegate.
    /// (The filename is SymbolsNerdFontMono-Regular.ttf but the PostScript name inside is SymbolsNFM.)
    private static let nerdFontName = "SymbolsNFM"

    /// Creates an NSFont for the given preset at the default size.
    /// Wraps the font with a cascade list that includes the bundled Nerd Font
    /// symbols, so Nerd Font glyphs (Powerline, Devicons, etc.) render correctly
    /// regardless of the user's chosen font.
    /// Falls back to monospacedSystemFont for "System Mono" or missing fonts.
    private static func makeFont(for preset: FontPreset) -> NSFont {
        let baseFont: NSFont
        if preset.displayName == defaultFontName {
            baseFont = NSFont.monospacedSystemFont(ofSize: defaultFontSize, weight: .regular)
        } else {
            baseFont = NSFont(name: preset.fontFamily, size: defaultFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: defaultFontSize, weight: .regular)
        }
        return addNerdFontCascade(to: baseFont)
    }

    /// Wraps a font with a cascade descriptor that includes the bundled
    /// Nerd Font symbols as a fallback. Core Text automatically uses the
    /// cascade font for any glyphs missing from the primary font.
    private static func addNerdFontCascade(to font: NSFont) -> NSFont {
        guard let nerdFont = NSFont(name: nerdFontName, size: font.pointSize) else {
            return font
        }
        let cascadeDescriptor = nerdFont.fontDescriptor
        let descriptor = font.fontDescriptor.addingAttributes([
            .cascadeList: [cascadeDescriptor]
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
