// DividerSplitView.swift
// Custom NSSplitView that draws themed divider lines natively, and
// a DividerGripView overlay for split views that live inside a parent container
// (e.g., terminal splits inside contentArea).

import AppKit

// MARK: - Themed Split View

/// NSSplitView subclass that draws themed 1px divider lines.
/// Used by NSSplitViewController subclasses (RootSplitViewController,
/// DualPaneExplorerViewController) where view == splitView, so overlay
/// subviews cannot be used (NSSplitView treats all subviews as panes,
/// causing phantom line artifacts and layout drift).
final class ThemedSplitView: NSSplitView {

    override var dividerThickness: CGFloat { 4 }

    override func drawDivider(in rect: NSRect) {
        let theme = ThemeManager.shared.activeTheme

        // Opaque 1px line blended from the theme — visible in both dark and light modes
        let borderColor = theme.backgroundColor.blended(
            withFraction: 0.3, of: theme.foregroundColor
        ) ?? theme.chromeBorder
        borderColor.setFill()

        if isVertical {
            let x = rect.minX + (rect.width - 1) / 2
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
        } else {
            let y = rect.minY + (rect.height - 1) / 2
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
        }
    }
}

// MARK: - Divider Grip View (for non-SVC split views)

/// A thin colored border overlaid on an NSSplitView divider.
/// Transparent except for a 1px line — adapts to theme via `chromeBorder`.
/// Forwards mouse events to the split view so the entire hit-target area is draggable.
///
/// Used only for split views that live inside a parent container (e.g., terminal
/// splits inside contentArea) where grips can be added to the container view
/// instead of the split view itself. For NSSplitViewController-based layouts,
/// use ThemedSplitView instead.
final class DividerGripView: NSView {

    /// Whether the parent split view is vertical (columns side-by-side).
    var isVerticalSplit = true {
        didSet { needsDisplay = true }
    }

    /// The divider index this grip represents.
    var dividerIndex = 0

    // Forward mouse events to the split view for divider dragging
    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        superview?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }

    // Show resize cursor when hovering over the divider
    override func resetCursorRects() {
        if isVerticalSplit {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        } else {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ThemeManager.shared.activeTheme

        // Opaque 1px line blended from the theme — visible in both dark and light modes
        let borderColor = theme.backgroundColor.blended(withFraction: 0.3, of: theme.foregroundColor)
            ?? theme.chromeBorder
        borderColor.setFill()
        if isVerticalSplit {
            let x = (bounds.width - 1) / 2
            NSRect(x: x, y: 0, width: 1, height: bounds.height).fill()
        } else {
            let y = (bounds.height - 1) / 2
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }
    }
}
