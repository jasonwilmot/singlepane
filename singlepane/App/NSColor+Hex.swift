// NSColor+Hex.swift
// Hex color string parsing for NSColor.
// Used by Theme, AppDelegate URL handling, and anywhere hex colors are needed.

import AppKit

extension NSColor {

    /// Creates an NSColor from a hex string (e.g. "#22C55E", "EAB308").
    /// Supports 6-character RGB hex with optional "#" prefix.
    /// Returns nil for invalid input.
    static func fromHex(_ hex: String) -> NSColor? {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }

        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0

        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Returns the hex string representation of this color (e.g. "22C55E").
    /// Falls back to "000000" if the color can't be converted to RGB.
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
