// TerminalGutterView.swift
// Thin vertical gutter drawn to the left of the terminal view.
// Displays colored dots for each command's exit code:
//   - Green dot (palette index 2) for exit code 0 (success)
//   - Red dot (palette index 1) for non-zero exit code (failure)
//
// Reads OSC 133 command marks from a TerminalSession and maps
// `.commandFinished` marks to visible row positions using the
// terminal buffer's scroll offset (yDisp).

import AppKit
import SwiftTerm

@MainActor
final class TerminalGutterView: NSView {

    // MARK: - Properties

    /// The gutter width in points. Narrow enough to not steal space from the terminal.
    static let gutterWidth: CGFloat = 12

    /// The session whose command marks are displayed.
    weak var session: TerminalSession?

    /// Cached cell height from the terminal view — used to align dots to rows.
    var cellHeight: CGFloat = 0

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let session, !session.commandMarks.isEmpty else { return }

        let terminal = session.terminalView.getTerminal()
        let yDisp = terminal.buffer.yDisp
        let visibleRows = terminal.rows

        let theme = ThemeManager.shared.activeTheme
        let successColor = theme.paletteColor(at: 2) // Green
        let failureColor = theme.paletteColor(at: 1) // Red

        let dotSize: CGFloat = 6
        let centerX = bounds.width / 2

        // Iterate prompt marks and draw exit code dots for visible ones.
        for mark in session.commandMarks where mark.type == .promptStart {
            // Find the exit code for this prompt's command.
            guard let exitCode = session.exitCode(forPromptAt: mark.absoluteLine) else { continue }

            // Convert absolute line to screen row relative to the current scroll position.
            let screenRow = mark.absoluteLine - yDisp
            guard screenRow >= 0, screenRow < visibleRows else { continue }

            // Terminal rows are top-down; NSView Y is bottom-up.
            let rowY = bounds.height - (CGFloat(screenRow) * cellHeight) - cellHeight

            let color = exitCode == 0 ? successColor : failureColor
            color.setFill()

            let dotRect = NSRect(
                x: centerX - dotSize / 2,
                y: rowY + (cellHeight - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    // MARK: - Updates

    /// Called when marks change, the terminal scrolls, or the view resizes.
    func refreshGutter() {
        needsDisplay = true
    }
}
