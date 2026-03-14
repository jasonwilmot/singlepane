// TabBarResizeHandle.swift
// Thin draggable handle for resizing the vertical tab bar width.
// Shows a resize cursor on hover and reports drag deltas to the owning container.

import AppKit

@MainActor
final class TabBarResizeHandle: NSView {

    /// Called with the horizontal drag delta on each mouseDragged event.
    var onDrag: ((CGFloat) -> Void)?

    /// Tracks the last mouse X position during a drag for delta computation.
    private var lastDragX: CGFloat = 0

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Draw a 1px vertical divider line centered in the handle
        let theme = ThemeManager.shared.activeTheme
        let color = theme.backgroundColor.blended(withFraction: 0.3, of: theme.foregroundColor)
            ?? theme.chromeBorder
        color.setFill()
        let x = (bounds.width - 1) / 2
        NSRect(x: x, y: 0, width: 1, height: bounds.height).fill()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        lastDragX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastDragX
        lastDragX = currentX
        onDrag?(delta)
    }
}
