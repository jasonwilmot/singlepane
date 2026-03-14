// TerminalLinkOverlayView.swift
// Transparent overlay that draws persistent underlines on detected links in terminal output.
// Layered on top of the SwiftTerm view. Underlines are always visible so the user knows
// which text is clickable. Updated periodically as terminal content changes.

import AppKit

@MainActor
final class TerminalLinkOverlayView: NSView {

    // MARK: - State

    /// All underline rectangles in view coordinates — one per detected link.
    private var underlineRects: [NSRect] = []

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

    /// Pass all mouse events through to the terminal view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - Underline Management

    /// Replaces all underlines with a new set of rectangles.
    /// Only triggers a redraw if the rects actually changed.
    func updateUnderlines(_ rects: [NSRect]) {
        guard underlineRects != rects else { return }
        underlineRects = rects
        needsDisplay = true
    }

    /// Removes all underlines.
    func clearUnderlines() {
        guard !underlineRects.isEmpty else { return }
        underlineRects = []
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !underlineRects.isEmpty else { return }

        // Theme-aware underline color — subtle but visible.
        let color = ThemeManager.shared.activeTheme.chromeText.withAlphaComponent(0.35)
        color.setFill()

        for rect in underlineRects where rect.intersects(dirtyRect) {
            rect.fill()
        }
    }
}
