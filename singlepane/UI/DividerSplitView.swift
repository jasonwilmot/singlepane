// DividerSplitView.swift
// Thin border overlay that sits on top of an NSSplitView divider.
// Forwards mouse drags to the split view so the full hit-target is grabbable.
// Repositions automatically when the split view resizes.

import AppKit

/// A thin colored border overlaid on an NSSplitView divider.
/// Transparent except for a 1px line — adapts to theme via `chromeBorder`.
/// Forwards mouse events to the split view so the entire hit-target area is draggable.
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

// MARK: - Installation Helper

extension NSSplitViewController {

    /// Adds grip overlay views on top of each divider in the split view.
    /// Call once in viewDidLoad after adding all split view items.
    /// Returns the overlays so the caller can keep a reference for theme updates.
    @discardableResult
    func installDividerGrips() -> [DividerGripView] {
        let sv = splitView
        let count = splitViewItems.count
        guard count > 1 else { return [] }

        var grips: [DividerGripView] = []
        for i in 0..<(count - 1) {
            let grip = DividerGripView()
            grip.isVerticalSplit = sv.isVertical
            grip.dividerIndex = i
            sv.addSubview(grip)
            grips.append(grip)
        }

        // Initial layout
        layoutDividerGrips(grips)

        // Reposition on every resize
        NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: sv,
            queue: .main
        ) { [weak self] _ in
            self?.layoutDividerGrips(grips)
        }

        return grips
    }

    /// Positions each grip overlay centered on its corresponding divider.
    /// Hides grips where either adjacent panel is collapsed.
    fileprivate func layoutDividerGrips(_ grips: [DividerGripView]) {
        let sv = splitView
        let items = splitViewItems
        let thickness: CGFloat = 4

        for (i, grip) in grips.enumerated() {
            // Hide grip when either adjacent panel is collapsed
            let leftCollapsed = items[i].isCollapsed
            let rightCollapsed = (i + 1 < items.count) ? items[i + 1].isCollapsed : true
            grip.isHidden = leftCollapsed || rightCollapsed

            guard !grip.isHidden, i < sv.subviews.count - grips.count else { continue }

            // The divider sits right after subview[i]
            let subviewFrame = sv.subviews[i].frame

            if sv.isVertical {
                let dividerX = subviewFrame.maxX
                grip.frame = NSRect(
                    x: dividerX - thickness / 2 + sv.dividerThickness / 2,
                    y: 0,
                    width: thickness,
                    height: sv.bounds.height
                )
            } else {
                let dividerY = subviewFrame.maxY
                grip.frame = NSRect(
                    x: 0,
                    y: dividerY - thickness / 2 + sv.dividerThickness / 2,
                    width: sv.bounds.width,
                    height: thickness
                )
            }

            grip.needsDisplay = true
        }
    }
}
