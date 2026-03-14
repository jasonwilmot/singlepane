// Theme.swift
// Defines the color slots for a global app theme.
// Each theme maps directly to Ghostty's terminal color format (~22 values),
// with UI chrome colors auto-derived from the terminal palette.

import AppKit

// MARK: - Theme

/// A complete app theme: terminal ANSI palette + derived UI chrome colors.
/// Stored as hex strings for Codable/JSON compatibility.
struct Theme: Codable, Sendable, Identifiable {

    /// Display name shown in the theme picker.
    let name: String

    /// Unique identifier — derived from name.
    var id: String { name }

    // MARK: - Terminal Colors (Ghostty-compatible)

    /// Terminal text color.
    let foreground: String

    /// Terminal background color.
    let background: String

    /// Cursor block color.
    let cursor: String

    /// Text color rendered under the cursor.
    let cursorText: String

    /// Background of selected text.
    let selectionBackground: String

    /// Foreground of selected text.
    let selectionForeground: String

    /// 16-color ANSI palette (indices 0–15).
    /// 0=black, 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white,
    /// 8–15 = bright variants.
    let palette: [String]

    // MARK: - NSColor Accessors (Terminal)

    var foregroundColor: NSColor { NSColor.fromHex(foreground) ?? .textColor }
    var backgroundColor: NSColor { NSColor.fromHex(background) ?? .textBackgroundColor }
    var cursorColor: NSColor { NSColor.fromHex(cursor) ?? .textColor }
    var cursorTextColor: NSColor { NSColor.fromHex(cursorText) ?? .textBackgroundColor }
    var selectionBackgroundColor: NSColor { NSColor.fromHex(selectionBackground) ?? .selectedTextBackgroundColor }
    var selectionForegroundColor: NSColor { NSColor.fromHex(selectionForeground) ?? .selectedTextColor }

    /// Returns an NSColor for the given ANSI palette index (0–15).
    func paletteColor(at index: Int) -> NSColor {
        guard index >= 0, index < palette.count else { return .textColor }
        return NSColor.fromHex(palette[index]) ?? .textColor
    }

    // MARK: - Derived Chrome Colors (auto-computed from terminal palette)

    /// Tab bar, layout bar, toolbar backgrounds — slightly lighter/darker than terminal bg.
    var chromeBackground: NSColor {
        backgroundColor.blended(withFraction: 0.15, of: foregroundColor)
            ?? backgroundColor
    }

    /// Dividers, separators — midpoint between bg and fg at low opacity.
    var chromeBorder: NSColor {
        foregroundColor.withAlphaComponent(0.2)
    }

    /// Primary text in chrome areas — matches terminal foreground.
    var chromeText: NSColor { foregroundColor }

    /// Dimmed/inactive text — terminal foreground at reduced opacity.
    var chromeTextSecondary: NSColor {
        foregroundColor.withAlphaComponent(0.5)
    }

    /// Selected tab, active layout icon, accent highlights — uses blue from palette.
    var chromeAccent: NSColor {
        paletteColor(at: 4) // Blue
    }

    /// File list background — matches terminal background.
    var explorerBackground: NSColor { backgroundColor }

    /// File list text — matches terminal foreground.
    var explorerText: NSColor { foregroundColor }

    /// Selected row highlight — accent blue at low opacity.
    var explorerSelection: NSColor {
        chromeAccent.withAlphaComponent(0.3)
    }

    /// Preview panel background — matches terminal background.
    var previewBackground: NSColor { backgroundColor }

    // MARK: - Hook Highlight Colors (adapted to theme)

    /// ANSI red (palette 1) for notification highlights.
    var hookRed: NSColor { paletteColor(at: 1) }

    /// ANSI green (palette 2) for stop/success highlights.
    var hookGreen: NSColor { paletteColor(at: 2) }

    /// ANSI yellow (palette 3) for prompt/thinking highlights.
    var hookYellow: NSColor { paletteColor(at: 3) }

    /// ANSI magenta (palette 5) for subagent highlights.
    var hookPurple: NSColor { paletteColor(at: 5) }

    // MARK: - Hex Helpers for CSS

    /// Returns the hex string (without #) for a given property.
    func hexString(for keyPath: KeyPath<Theme, String>) -> String {
        let value = self[keyPath: keyPath]
        return value.hasPrefix("#") ? String(value.dropFirst()) : value
    }
}
