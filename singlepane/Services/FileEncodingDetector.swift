// FileEncodingDetector.swift
// Detects file encoding, line endings, and indentation style from raw file bytes.
//
// Encoding detection:
//   1. Check for BOM (UTF-8 BOM, UTF-16 LE/BE, UTF-32 LE/BE)
//   2. Fall back to NSString.stringEncoding(for:) heuristics
//   3. Default to UTF-8 if detection fails
//
// Line ending detection:
//   Scans text for \r\n, \n, \r and reports the dominant type (or mixed).
//
// Indent style detection:
//   Scans leading whitespace of the first N indented lines to determine
//   tabs vs spaces and the most common space count.

import Foundation

// MARK: - Line Ending Type

/// The line ending convention detected in a file.
enum LineEnding: String {
    case lf    = "LF"
    case crlf  = "CRLF"
    case cr    = "CR"
    case mixed = "Mixed"

    /// The raw character sequence for this line ending type.
    var characters: String {
        switch self {
        case .lf:    "\n"
        case .crlf:  "\r\n"
        case .cr:    "\r"
        case .mixed: "\n" // default to LF for mixed
        }
    }
}

// MARK: - Indent Style

/// The indentation style detected in a file.
enum IndentStyle: Equatable {
    case spaces(Int)
    case tabs

    /// Human-readable label for the status bar.
    var displayName: String {
        switch self {
        case .spaces(let count): "Spaces: \(count)"
        case .tabs:              "Tabs"
        }
    }

    /// The string inserted for one indent level.
    var indentString: String {
        switch self {
        case .spaces(let count): String(repeating: " ", count: count)
        case .tabs:              "\t"
        }
    }
}

// MARK: - Encoding Display

/// Human-readable names for common encodings.
/// Used by the status bar and encoding menus.
enum EncodingInfo {

    /// Common encodings offered in the status bar menus, ordered by frequency.
    static let commonEncodings: [(name: String, encoding: String.Encoding)] = [
        ("UTF-8",            .utf8),
        ("UTF-16 LE",        .utf16LittleEndian),
        ("UTF-16 BE",        .utf16BigEndian),
        ("ASCII",            .ascii),
        ("Latin-1 (ISO 8859-1)", .isoLatin1),
        ("Latin-2 (ISO 8859-2)", .isoLatin2),
        ("Windows-1252",     .windowsCP1252),
        ("Windows-1250",     .windowsCP1250),
        ("Windows-1251",     .windowsCP1251),
        ("Shift-JIS",        .shiftJIS),
        ("EUC-JP",           .japaneseEUC),
        ("ISO-2022-JP",      .iso2022JP),
        ("Mac Roman",        .macOSRoman),
        ("UTF-32 LE",        .utf32LittleEndian),
        ("UTF-32 BE",        .utf32BigEndian),
    ]

    /// Returns a human-readable name for the given encoding.
    static func displayName(for encoding: String.Encoding) -> String {
        commonEncodings.first(where: { $0.encoding == encoding })?.name
            ?? encoding.description
    }
}

// MARK: - File Encoding Detector

/// Stateless utilities for detecting file encoding, line endings, and indent style.
enum FileEncodingDetector {

    // MARK: - Encoding Detection

    /// Detects the encoding of a file by reading its raw bytes.
    /// Checks BOM first, then falls back to NSString heuristics, then UTF-8.
    static func detectEncoding(at url: URL) -> String.Encoding {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .utf8
        }
        return detectEncoding(from: data)
    }

    /// Detects encoding from raw data bytes.
    static func detectEncoding(from data: Data) -> String.Encoding {
        // Check BOM signatures first — these are definitive
        if let bomEncoding = detectBOM(in: data) {
            return bomEncoding
        }

        // Fall back to NSString's heuristic detection
        // This uses ICU internally for charset detection
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    String.Encoding.utf8.rawValue,
                    String.Encoding.isoLatin1.rawValue,
                    String.Encoding.windowsCP1252.rawValue,
                    String.Encoding.macOSRoman.rawValue,
                    String.Encoding.shiftJIS.rawValue,
                    String.Encoding.japaneseEUC.rawValue,
                ],
                .useOnlySuggestedEncodingsKey: false,
            ],
            convertedString: nil,
            usedLossyConversion: &usedLossyConversion
        )

        // NSString returns 0 when detection fails
        if detected != 0 {
            return String.Encoding(rawValue: detected)
        }

        return .utf8
    }

    /// Checks for Byte Order Mark at the start of the data.
    /// BOM detection is ordered from longest signature to shortest to avoid
    /// false matches (e.g., UTF-32 LE starts with the same bytes as UTF-16 LE + NUL).
    private static func detectBOM(in data: Data) -> String.Encoding? {
        let bytes = Array(data.prefix(4))
        let count = bytes.count

        // UTF-32 LE: FF FE 00 00
        if count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE
            && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return .utf32LittleEndian
        }

        // UTF-32 BE: 00 00 FE FF
        if count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00
            && bytes[2] == 0xFE && bytes[3] == 0xFF {
            return .utf32BigEndian
        }

        // UTF-8 BOM: EF BB BF
        if count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return .utf8
        }

        // UTF-16 LE: FF FE (must check after UTF-32 LE)
        if count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return .utf16LittleEndian
        }

        // UTF-16 BE: FE FF
        if count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return .utf16BigEndian
        }

        return nil
    }

    // MARK: - Line Ending Detection

    /// Detects the dominant line ending type in the given text.
    /// Scans the full string counting occurrences of each type.
    /// Returns `.lf` as default for empty or single-line files.
    static func detectLineEndings(in text: String) -> LineEnding {
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0

        let chars = text.utf8
        var iterator = chars.makeIterator()
        var prev: UInt8?

        while let byte = iterator.next() {
            if byte == 0x0A { // \n
                if prev == 0x0D {
                    // This \n follows a \r — count as CRLF, undo the CR count
                    crCount -= 1
                    crlfCount += 1
                } else {
                    lfCount += 1
                }
            } else if byte == 0x0D { // \r
                crCount += 1
            }
            prev = byte
        }

        let total = crlfCount + lfCount + crCount
        if total == 0 { return .lf }

        // Check for mixed line endings
        let types = [crlfCount > 0, lfCount > 0, crCount > 0].filter { $0 }.count
        if types > 1 { return .mixed }

        if crlfCount > 0 { return .crlf }
        if crCount > 0 { return .cr }
        return .lf
    }

    // MARK: - Indent Style Detection

    /// Detects the indentation style by scanning leading whitespace
    /// of the first `maxLines` indented lines.
    /// Returns `.spaces(4)` as default when no indentation is found.
    static func detectIndentStyle(in text: String, maxLines: Int = 500) -> IndentStyle {
        var tabLines = 0
        var spaceLines = 0
        var spaceCounts: [Int: Int] = [:] // space count → frequency
        var linesScanned = 0

        for line in text.split(separator: "\n", maxSplits: maxLines, omittingEmptySubsequences: false) {
            guard linesScanned < maxLines else { break }
            linesScanned += 1

            guard let first = line.first else { continue }

            if first == "\t" {
                tabLines += 1
            } else if first == " " {
                spaceLines += 1
                let spaceCount = line.prefix(while: { $0 == " " }).count
                // Only count common indent widths (2, 3, 4, 6, 8)
                if spaceCount >= 2 && spaceCount <= 8 {
                    spaceCounts[spaceCount, default: 0] += 1
                }
            }
        }

        if tabLines > spaceLines {
            return .tabs
        }

        if spaceLines > 0 {
            // Find the most common space count, preferring smaller widths as tie-breaker
            let bestWidth = spaceCounts
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .first?.key ?? 4

            // Derive the indent unit — if the most common count is 6 but 2-space lines
            // are also common, the indent unit is likely 2
            let gcd = spaceCounts.keys.reduce(0) { gcdImpl($0, $1) }
            let unit = gcd >= 2 ? gcd : bestWidth
            return .spaces(min(unit, 8))
        }

        return .spaces(4)
    }

    /// Greatest common divisor helper for indent width detection.
    private static func gcdImpl(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcdImpl(b, a % b)
    }
}
