// TerminalHintsOverlayView.swift
// Full-screen overlay rendered on top of a terminal view during hints mode.
// Draws letter label badges on each detected link and dims the terminal content.
// Hit-tests pass through to the hints controller's event monitor — this view
// is purely visual (like TerminalLinkOverlayView).

import AppKit

/// A single hint to render: its label text, the highlight rect, and the badge position.
struct HintAnnotation {
    /// The letter label displayed on the badge (e.g. "a", "ab").
    let label: String
    /// The highlight rect covering the matched text in view coordinates.
    let highlightRect: NSRect
    /// The top-left position for the badge in view coordinates.
    let badgeOrigin: NSPoint
}

@MainActor
final class TerminalHintsOverlayView: NSView {

    // MARK: - State

    /// All hint annotations to render. Set by the hints controller on activation.
    private var annotations: [HintAnnotation] = []

    /// Whether the overlay is in active hints mode (dims background, shows labels).
    private var isActive: Bool = false

    // MARK: - Appearance Constants

    /// Background dim applied to the terminal content behind the overlay.
    private static let dimAlpha: CGFloat = 0.45

    /// Corner radius for the label badge.
    private static let badgeCornerRadius: CGFloat = 3

    /// Horizontal padding inside the label badge.
    private static let badgePaddingH: CGFloat = 3

    /// Vertical padding inside the label badge.
    private static let badgePaddingV: CGFloat = 1

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Hit Testing

    /// Pass all mouse events through — hints mode uses keyboard event monitors,
    /// not mouse interaction on this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - Activation

    /// Shows the hints overlay with the given annotations. Triggers a full redraw.
    func activate(annotations: [HintAnnotation]) {
        self.annotations = annotations
        self.isActive = true
        isHidden = false
        needsDisplay = true
    }

    /// Hides the hints overlay and clears all annotations.
    func deactivate() {
        self.annotations = []
        self.isActive = false
        isHidden = true
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard isActive else { return }

        let theme = ThemeManager.shared.activeTheme

        // 1. Dim the entire terminal area
        theme.backgroundColor.withAlphaComponent(Self.dimAlpha).setFill()
        dirtyRect.fill()

        // 2. Draw highlight backgrounds and label badges for each annotation
        let highlightColor = theme.chromeAccent.withAlphaComponent(0.25)
        let badgeBg = theme.chromeAccent
        let badgeText = theme.cursorTextColor
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: badgeText,
        ]

        for annotation in annotations {
            // Highlight rect behind the matched text
            highlightColor.setFill()
            annotation.highlightRect.fill()

            // Measure label text to size the badge
            let labelStr = annotation.label as NSString
            let textSize = labelStr.size(withAttributes: textAttributes)

            let badgeWidth = textSize.width + Self.badgePaddingH * 2
            let badgeHeight = textSize.height + Self.badgePaddingV * 2
            let badgeRect = NSRect(
                x: annotation.badgeOrigin.x,
                y: annotation.badgeOrigin.y,
                width: badgeWidth,
                height: badgeHeight
            )

            // Badge background — rounded rect
            let badgePath = NSBezierPath(
                roundedRect: badgeRect,
                xRadius: Self.badgeCornerRadius,
                yRadius: Self.badgeCornerRadius
            )
            badgeBg.setFill()
            badgePath.fill()

            // Badge letter
            let textOrigin = NSPoint(
                x: badgeRect.origin.x + Self.badgePaddingH,
                y: badgeRect.origin.y + Self.badgePaddingV
            )
            labelStr.draw(at: textOrigin, withAttributes: textAttributes)
        }
    }
}
