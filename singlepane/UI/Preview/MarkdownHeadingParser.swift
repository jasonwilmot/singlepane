// MarkdownHeadingParser.swift
// Extracts heading entries (H1–H6) from markdown text for the outline view.
// Reuses the same regex patterns and palette indices as MarkdownSyntaxHighlighter
// so outline styling is consistent with the editor's heading colors.

import Foundation

/// A single heading extracted from a markdown document.
struct MarkdownHeading {
    /// Heading level: 1 for H1, 2 for H2, ... 6 for H6.
    let level: Int

    /// The heading text content (without `#` markers).
    let title: String

    /// Character range of the full heading line in the source text.
    let range: NSRange

    /// Stable anchor ID for HTML scroll-to-heading.
    /// Not used directly — preview mode uses the heading's array index instead.
    var anchorID: String { "heading-\(range.location)" }
}

/// Parses markdown text and extracts heading entries.
/// Shared by MarkdownOutlineView and the HTML converter for consistent heading IDs.
enum MarkdownHeadingParser {

    /// Heading level colors mapped to theme ANSI palette indices.
    /// Mirrors MarkdownSyntaxHighlighter.headingPaletteIndices.
    static let paletteIndices: [Int] = [
        4,   // H1 → Blue
        5,   // H2 → Magenta
        6,   // H3 → Cyan
        2,   // H4 → Green
        3,   // H5 → Yellow
        1,   // H6 → Red
    ]

    /// Font size scales per heading level, mirroring MarkdownSyntaxHighlighter.
    static let fontScales: [CGFloat] = [1.8, 1.5, 1.3, 1.15, 1.05, 1.0]

    /// Extracts all headings from the given markdown text.
    /// Returns an ordered array of headings with their levels, titles, and source ranges.
    static func parse(_ text: String) -> [MarkdownHeading] {
        guard let regex = try? NSRegularExpression(
            pattern: "^(#{1,6})\\s+(.+)$",
            options: .anchorsMatchLines
        ) else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var headings: [MarkdownHeading] = []

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let hashRange = match.range(at: 1)
            let titleRange = match.range(at: 2)
            let level = hashRange.length
            let title = nsText.substring(with: titleRange)

            headings.append(MarkdownHeading(
                level: level,
                title: title,
                range: match.range(at: 0)
            ))
        }

        return headings
    }
}
