// MarkdownSyntaxHighlighter.swift
// Applies visual syntax highlighting to markdown text in an NSTextView.
// Uses regex patterns to style headings, bold, italic, code, links, etc.
// Colors are derived from the active theme's ANSI palette for consistency.
//
// iA Writer-style layout: heading `#` markers are left-flush in the margin,
// body text is indented to a consistent position. Each heading level gets a
// distinct color from the theme palette.

import AppKit

@MainActor
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate, SyntaxHighlighting {

    // MARK: - Properties

    private weak var textView: NSTextView?

    // MARK: - Layout Constants

    /// Indentation for body text, lists, and other non-heading content.
    /// Heading `#` markers hang into the margin to the left of this position.
    private static let bodyIndent: CGFloat = 40

    // MARK: - Init

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        textView.textStorage?.delegate = self
    }

    // MARK: - NSTextStorageDelegate

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Only re-highlight when characters changed, not just attributes
        guard editedMask.contains(.editedCharacters) else { return }

        Task { @MainActor [weak self] in
            self?.highlightAll()
        }
    }

    // MARK: - Highlighting

    /// Applies syntax highlighting to the full text content.
    func highlightAll() {
        guard let textStorage = textView?.textStorage else { return }
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let theme = ThemeManager.shared.activeTheme
        let baseFont = FontManager.shared.activeFont
        let baseFontSize = baseFont.pointSize

        // Default paragraph style: body-level indent for all text
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.firstLineHeadIndent = Self.bodyIndent
        bodyParagraph.headIndent = Self.bodyIndent

        // Reset to base style with body indentation
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: theme.foregroundColor,
            .paragraphStyle: bodyParagraph,
        ], range: fullRange)

        // Apply patterns — order matters (later rules override earlier ones)
        applyBlockquotes(textStorage, text: text, theme: theme, baseFont: baseFont)
        applyListItems(textStorage, text: text, theme: theme, baseFont: baseFont)
        applyHorizontalRules(textStorage, text: text, theme: theme)
        applyCodeBlocks(textStorage, text: text, theme: theme, baseFont: baseFont, baseFontSize: baseFontSize)
        applyInlineCode(textStorage, text: text, theme: theme, baseFont: baseFont, baseFontSize: baseFontSize)
        applyHeadings(textStorage, text: text, theme: theme, baseFont: baseFont, baseFontSize: baseFontSize)
        applyBold(textStorage, text: text, theme: theme, baseFont: baseFont, baseFontSize: baseFontSize)
        applyItalic(textStorage, text: text, theme: theme, baseFont: baseFont, baseFontSize: baseFontSize)
        applyLinks(textStorage, text: text, theme: theme)

        textStorage.endEditing()
    }

    // MARK: - Pattern Helpers

    /// Matches a regex and applies attributes to each match.
    private func applyPattern(
        _ pattern: String,
        to textStorage: NSTextStorage,
        text: String,
        options: NSRegularExpression.Options = [],
        attributes: [NSAttributedString.Key: Any],
        group: Int = 0
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, let range = Range(match.range(at: group), in: text) else { return }
            let nsRange = NSRange(range, in: text)
            textStorage.addAttributes(attributes, range: nsRange)
        }
    }

    // MARK: - Headings

    /// Heading level colors mapped to theme ANSI palette indices.
    /// Each level gets a distinct color for visual hierarchy.
    private static let headingPaletteIndices: [Int] = [
        4,   // H1 → Blue
        5,   // H2 → Magenta
        6,   // H3 → Cyan
        2,   // H4 → Green
        3,   // H5 → Yellow
        1,   // H6 → Red
    ]

    private func applyHeadings(
        _ ts: NSTextStorage, text: String, theme: Theme,
        baseFont: NSFont, baseFontSize: CGFloat
    ) {
        // H1–H6: lines starting with 1–6 # characters.
        // Each level has a unique size scale, color, and hanging indent.
        //
        // Hanging indent layout: the `#` markers hang into the left margin while
        // the heading TEXT content aligns with body text at `bodyIndent`.
        // `firstLineHeadIndent` = bodyIndent - width("## ") so `#` sits in margin.
        // `headIndent` = bodyIndent so wrapped lines align with body text.
        let headingDefs: [(pattern: String, scale: CGFloat, level: Int, hashCount: Int)] = [
            ("^#{1}\\s+.+$", 1.8, 0, 1),   // # H1
            ("^#{2}\\s+.+$", 1.5, 1, 2),   // ## H2
            ("^#{3}\\s+.+$", 1.3, 2, 3),   // ### H3
            ("^#{4}\\s+.+$", 1.15, 3, 4),  // #### H4
            ("^#{5}\\s+.+$", 1.05, 4, 5),  // ##### H5
            ("^#{6}\\s+.+$", 1.0, 5, 6),   // ###### H6
        ]

        // Apply from H6 to H1 so larger headings take priority
        for (pattern, scale, level, hashCount) in headingDefs.reversed() {
            let font = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold),
                              size: baseFontSize * scale) ?? baseFont
            let colorIndex = Self.headingPaletteIndices[level]

            // Measure the width of the `# ` prefix in the heading's own font
            // so we know how far left to hang it from bodyIndent.
            let prefix = String(repeating: "#", count: hashCount) + " "
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            let firstLineIndent = max(Self.bodyIndent - prefixWidth, 0)

            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.firstLineHeadIndent = firstLineIndent
            headingParagraph.headIndent = Self.bodyIndent

            applyPattern(pattern, to: ts, text: text, options: .anchorsMatchLines, attributes: [
                .font: font,
                .foregroundColor: theme.paletteColor(at: colorIndex),
                .paragraphStyle: headingParagraph,
            ])
        }
    }

    // MARK: - Bold

    private func applyBold(
        _ ts: NSTextStorage, text: String, theme: Theme,
        baseFont: NSFont, baseFontSize: CGFloat
    ) {
        let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold),
                              size: baseFontSize) ?? baseFont
        // **bold** or __bold__
        applyPattern("(?:\\*\\*|__)(.+?)(?:\\*\\*|__)", to: ts, text: text, attributes: [
            .font: boldFont,
            .foregroundColor: theme.paletteColor(at: 4), // Blue — matches H1 heading color
        ])
    }

    // MARK: - Italic

    private func applyItalic(
        _ ts: NSTextStorage, text: String, theme: Theme,
        baseFont: NSFont, baseFontSize: CGFloat
    ) {
        let italicFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic),
                                size: baseFontSize) ?? baseFont
        // *italic* or _italic_ (single delimiter, not double)
        applyPattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
                     to: ts, text: text, attributes: [
            .font: italicFont,
        ])
    }

    // MARK: - Inline Code

    private func applyInlineCode(
        _ ts: NSTextStorage, text: String, theme: Theme,
        baseFont: NSFont, baseFontSize: CGFloat
    ) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
        // `inline code` — single backticks, not inside fenced blocks
        applyPattern("`([^`\n]+)`", to: ts, text: text, attributes: [
            .font: monoFont,
            .foregroundColor: theme.paletteColor(at: 2), // Green
            .backgroundColor: theme.foregroundColor.withAlphaComponent(0.07),
        ])
    }

    // MARK: - Code Blocks

    private func applyCodeBlocks(
        _ ts: NSTextStorage, text: String, theme: Theme,
        baseFont: NSFont, baseFontSize: CGFloat
    ) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
        // Fenced code blocks: ```...```
        applyPattern("```[\\s\\S]*?```", to: ts, text: text, attributes: [
            .font: monoFont,
            .foregroundColor: theme.paletteColor(at: 2), // Green
            .backgroundColor: theme.foregroundColor.withAlphaComponent(0.05),
        ])
    }

    // MARK: - Links

    private func applyLinks(_ ts: NSTextStorage, text: String, theme: Theme) {
        // [text](url)
        applyPattern("\\[([^\\]]+)\\]\\([^)]+\\)", to: ts, text: text, attributes: [
            .foregroundColor: theme.paletteColor(at: 6), // Cyan
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
    }

    // MARK: - Blockquotes

    private func applyBlockquotes(
        _ ts: NSTextStorage, text: String, theme: Theme, baseFont: NSFont
    ) {
        // Lines starting with >
        applyPattern("^>\\s?.*$", to: ts, text: text, options: .anchorsMatchLines, attributes: [
            .foregroundColor: theme.chromeTextSecondary,
        ])
    }

    // MARK: - List Items

    private func applyListItems(
        _ ts: NSTextStorage, text: String, theme: Theme, baseFont: NSFont
    ) {
        // Unordered: - or * or + at line start (with optional indent)
        applyPattern("^\\s*[-*+]\\s", to: ts, text: text, options: .anchorsMatchLines, attributes: [
            .foregroundColor: theme.paletteColor(at: 3), // Yellow
        ])
        // Ordered: 1. 2. etc.
        applyPattern("^\\s*\\d+\\.\\s", to: ts, text: text, options: .anchorsMatchLines, attributes: [
            .foregroundColor: theme.paletteColor(at: 3), // Yellow
        ])
    }

    // MARK: - Horizontal Rules

    private func applyHorizontalRules(_ ts: NSTextStorage, text: String, theme: Theme) {
        // --- or *** or ___ on their own line
        applyPattern("^[-*_]{3,}$", to: ts, text: text, options: .anchorsMatchLines, attributes: [
            .foregroundColor: theme.chromeBorder,
        ])
    }
}
