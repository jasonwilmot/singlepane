// LineNumberGutterView.swift
// Custom NSView that draws line numbers in a gutter alongside an NSTextView.
// Shared between CodePreviewViewController (read-only) and EditorViewController (editable).
//
// Positioned next to the scroll view via auto-layout constraints. Scroll sync is handled
// by the parent view controller observing NSView.boundsDidChangeNotification on the clip view.
//
// Features:
//   - Auto-sizes width based on digit count
//   - Theme-aware background, text color, and separator line
//   - Font-aware, scaled to 85% of the active font size
//   - Click-to-select entire line
//   - Optional current line highlight (for editor use)

import AppKit

@MainActor
final class LineNumberGutterView: NSView {

    // MARK: - Configuration

    /// The text view whose lines are numbered.
    weak var textView: NSTextView?

    /// When true, draws a subtle highlight band on the line containing the insertion point.
    var highlightsCurrentLine = false

    /// Offset added to displayed line numbers. Used by mmap mode where the text view
    /// contains only a window of lines starting at this offset (0-based).
    var lineNumberOffset: Int = 0

    /// When set, overrides the text view's line count for width calculation.
    /// Used by mmap mode to size the gutter for the total file line count.
    var overrideTotalLineCount: Int?

    // MARK: - Constants

    /// Horizontal padding inside the gutter (leading and trailing).
    private static let horizontalPadding: CGFloat = 8

    /// Font size scale relative to the active font (slightly smaller than code text).
    private static let fontSizeScale: CGFloat = 0.85

    /// Minimum gutter width to avoid clipping single-digit numbers.
    private static let minimumWidth: CGFloat = 32

    /// Width constraint managed internally for auto-sizing.
    private var widthConstraint: NSLayoutConstraint?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // Use top-down coordinates to match NSTextView's layout direction.
    override var isFlipped: Bool { true }

    // MARK: - Width Management

    /// Recalculates and updates the gutter width based on the current line count.
    func updateWidth() {
        guard let textView else { return }

        let lineCount: Int
        if let override = overrideTotalLineCount {
            lineCount = max(override, 1)
        } else {
            lineCount = max(textView.string.components(separatedBy: "\n").count, 1)
        }
        let digits = CGFloat(String(lineCount).count)
        let font = gutterFont()
        let sampleWidth = NSString(string: "8").size(withAttributes: [.font: font]).width
        let width = (digits * sampleWidth) + (Self.horizontalPadding * 2)
        let targetWidth = max(width, Self.minimumWidth)

        if let existing = widthConstraint {
            existing.constant = targetWidth
        } else {
            let wc = widthAnchor.constraint(equalToConstant: targetWidth)
            wc.isActive = true
            widthConstraint = wc
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView
        else { return }

        let theme = ThemeManager.shared.activeTheme
        let font = gutterFont()

        // Fill gutter background
        theme.chromeBackground.setFill()
        dirtyRect.fill()

        // Draw separator line on trailing edge
        let separatorX = bounds.maxX - 0.5
        theme.chromeBorder.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: separatorX, y: dirtyRect.minY))
        separator.line(to: NSPoint(x: separatorX, y: dirtyRect.maxY))
        separator.lineWidth = 1
        separator.stroke()

        // Text attributes for line numbers
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.chromeTextSecondary,
            .paragraphStyle: paragraphStyle,
        ]

        // Current line detection (editor only)
        let currentLineIndex: Int? = highlightsCurrentLine
            ? lineIndex(at: textView.selectedRange().location, in: textView)
            : nil

        // Get the visible rect from the scroll view's clip view
        let visibleRect = scrollView.contentView.bounds
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        let text = textView.string as NSString
        let textContainerInset = textView.textContainerInset

        var lineNumber = text.substring(to: visibleCharRange.location)
            .components(separatedBy: "\n").count + lineNumberOffset

        var charIndex = visibleCharRange.location
        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))

            // Get the rect for this line's first glyph
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)

            // Convert from text view coordinates to gutter coordinates:
            // Add text container inset, subtract scroll offset
            lineRect.origin.y += textContainerInset.height
            lineRect.origin.y -= visibleRect.origin.y

            // Draw current line highlight
            if let currentLine = currentLineIndex, lineNumber == currentLine {
                let highlightColor = theme.chromeAccent.withAlphaComponent(0.08)
                highlightColor.setFill()
                let highlightRect = NSRect(x: 0, y: lineRect.origin.y, width: bounds.width, height: lineRect.height)
                highlightRect.fill()
            }

            // Draw the line number right-aligned with trailing padding
            let numberString = "\(lineNumber)"
            let drawRect = NSRect(
                x: 0,
                y: lineRect.origin.y,
                width: bounds.width - Self.horizontalPadding,
                height: lineRect.height
            )
            (numberString as NSString).draw(in: drawRect, withAttributes: attributes)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }
    }

    // MARK: - Click to Select Line

    override func mouseDown(with event: NSEvent) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView
        else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let visibleRect = scrollView.contentView.bounds
        let textContainerInset = textView.textContainerInset

        // Convert click point to text view coordinates
        let textPoint = NSPoint(x: 0, y: point.y + visibleRect.origin.y - textContainerInset.height)

        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))

        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
    }

    // MARK: - Helpers

    /// Returns the active font scaled down for the gutter.
    private func gutterFont() -> NSFont {
        let baseFont = FontManager.shared.activeFont
        let scaledSize = baseFont.pointSize * Self.fontSizeScale
        return NSFont(descriptor: baseFont.fontDescriptor, size: scaledSize)
            ?? NSFont.monospacedSystemFont(ofSize: scaledSize, weight: .regular)
    }

    /// Returns the 1-based line number for a character index in the text view.
    private func lineIndex(at characterIndex: Int, in textView: NSTextView) -> Int? {
        let text = textView.string as NSString
        guard characterIndex <= text.length else { return nil }
        let upToIndex = text.substring(to: min(characterIndex, text.length))
        return upToIndex.components(separatedBy: "\n").count
    }
}
