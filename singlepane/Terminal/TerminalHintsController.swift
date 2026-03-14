// TerminalHintsController.swift
// Modal state machine for hints/quick-select mode.
// Activation: scans all visible terminal panes for URLs, file paths, and git hashes.
// Assigns sequential letter labels (a–z, then aa–az) to each match.
// Captures keyboard input — pressing a label key fires the associated action.
//
// Actions:
//   lowercase letter  → default action (open URL / reveal file / copy hash)
//   Shift+letter      → copy matched text to clipboard
//   Option+letter     → insert matched text at terminal cursor
//   Escape / click    → dismiss without action

import AppKit
import SwiftTerm

// MARK: - Hint Match

/// A detected match in a specific terminal session, positioned for overlay rendering.
struct HintMatch {
    /// The label assigned to this match (e.g. "a", "ab").
    let label: String
    /// The detected link (URL, file path, or git hash).
    let link: DetectedLink
    /// The session this match belongs to.
    let sessionID: UUID
    /// The screen row (0-based from top of visible area) where the match starts.
    let screenRow: Int
    /// The column range of the match within the line.
    let columnStart: Int
    let columnLength: Int
}

// MARK: - Hint Action

/// The action to perform when a hint label is selected.
enum HintAction {
    /// Default action — open URL, reveal file, copy hash.
    case defaultAction
    /// Copy the matched text to the system clipboard.
    case copy
    /// Insert the matched text at the active terminal cursor.
    case insertAtCursor
}

// MARK: - Hints Delegate

/// Delegate protocol for routing hint actions back to the container.
@MainActor
protocol TerminalHintsDelegate: AnyObject {
    /// Called when the user selects a hint. The container handles the action routing.
    func hintsController(
        _ controller: TerminalHintsController,
        didSelect match: HintMatch,
        action: HintAction
    )
    /// Called when hints mode is dismissed (by Escape, click, or after action).
    func hintsControllerDidDismiss(_ controller: TerminalHintsController)
}

// MARK: - Hints Controller

@MainActor
final class TerminalHintsController {

    // MARK: - Properties

    /// Whether hints mode is currently active.
    private(set) var isActive: Bool = false

    /// All matches found during the current hints session.
    private var matches: [HintMatch] = []

    /// Map from label string to match for fast lookup on key press.
    private var labelMap: [String: HintMatch] = [:]

    /// Per-session overlay views, keyed by session ID.
    private var overlays: [UUID: TerminalHintsOverlayView] = [:]

    /// Event monitor capturing keyboard input during hints mode.
    nonisolated(unsafe) private var keyMonitor: Any?

    /// Event monitor capturing mouse clicks to dismiss hints mode.
    nonisolated(unsafe) private var clickMonitor: Any?

    /// Delegate for routing actions.
    weak var delegate: TerminalHintsDelegate?

    // MARK: - Label Generation

    /// Generates sequential labels: a, b, c, ..., z, aa, ab, ..., az.
    private static func generateLabels(count: Int) -> [String] {
        var labels: [String] = []
        let chars = Array("abcdefghijklmnopqrstuvwxyz")

        // Single-letter labels first (a–z)
        for i in 0..<min(count, 26) {
            labels.append(String(chars[i]))
        }

        // Two-letter labels if needed (aa–az, ba–bz, ...)
        if count > 26 {
            for i in 26..<count {
                let first = chars[(i - 26) / 26]
                let second = chars[(i - 26) % 26]
                labels.append(String(first) + String(second))
            }
        }

        return labels
    }

    // MARK: - Activation

    /// Scans all visible sessions for actionable patterns and enters hints mode.
    /// - Parameters:
    ///   - sessions: The currently visible terminal sessions.
    ///   - cellDimensions: A closure that returns (width, height) for a terminal view's cells.
    func activate(
        sessions: [TerminalSession],
        cellDimensions: (LocalProcessTerminalView) -> (width: CGFloat, height: CGFloat)
    ) {
        guard !isActive else { return }

        // Scan all visible sessions for matches
        var allMatches: [HintMatch] = []

        for session in sessions {
            let terminal = session.terminalView.getTerminal()

            for screenRow in 0..<terminal.rows {
                let bufferRow = screenRow + terminal.buffer.yDisp
                let lineStart = Position(col: 0, row: bufferRow)
                let lineEnd = Position(col: terminal.cols - 1, row: bufferRow)
                let lineText = terminal.getText(start: lineStart, end: lineEnd)
                    .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)

                guard !lineText.isEmpty else { continue }

                let links = TerminalLinkDetector.detectAllPatterns(
                    in: lineText, cwd: session.currentDirectory
                )

                for link in links {
                    guard let colRange = TerminalLinkDetector.columnRange(
                        for: link, in: lineText
                    ) else { continue }

                    // Placeholder label — assigned after collecting all matches
                    allMatches.append(HintMatch(
                        label: "",
                        link: link,
                        sessionID: session.id,
                        screenRow: screenRow,
                        columnStart: colRange.start,
                        columnLength: colRange.length
                    ))
                }
            }
        }

        guard !allMatches.isEmpty else { return }

        // Assign labels (bottom of screen first — closest to where user is typing)
        let labels = Self.generateLabels(count: allMatches.count)
        // Sort matches by row descending so bottom-of-screen matches get short labels
        let sorted = allMatches.enumerated().sorted { a, b in
            a.element.screenRow > b.element.screenRow
        }
        matches = sorted.map { index, match in
            HintMatch(
                label: labels[index],
                link: match.link,
                sessionID: match.sessionID,
                screenRow: match.screenRow,
                columnStart: match.columnStart,
                columnLength: match.columnLength
            )
        }

        // Build label lookup map
        labelMap = Dictionary(uniqueKeysWithValues: matches.map { ($0.label, $0) })

        // Create overlay annotations per session
        for session in sessions {
            let sessionMatches = matches.filter { $0.sessionID == session.id }
            guard !sessionMatches.isEmpty else { continue }

            let terminalView = session.terminalView
            let cell = cellDimensions(terminalView)
            let bounds = terminalView.bounds

            let annotations: [HintAnnotation] = sessionMatches.map { match in
                let x = CGFloat(match.columnStart) * cell.width
                let y = bounds.height - CGFloat(match.screenRow + 1) * cell.height
                let width = CGFloat(match.columnLength) * cell.width

                let highlightRect = NSRect(x: x, y: y, width: width, height: cell.height)

                // Shift badge left so it doesn't obscure the first character of the match.
                // Offset by label character count + 1 cell widths, clamped to 0.
                let labelChars = CGFloat(match.label.count + 1)
                let badgeX = max(x - labelChars * cell.width, 0)
                let badgeOrigin = NSPoint(x: badgeX, y: y)

                return HintAnnotation(
                    label: match.label,
                    highlightRect: highlightRect,
                    badgeOrigin: badgeOrigin
                )
            }

            let overlay = ensureOverlay(for: session)
            overlay.frame = bounds
            overlay.activate(annotations: annotations)
        }

        isActive = true
        installEventMonitors()
    }

    // MARK: - Deactivation

    /// Exits hints mode, removes overlays, and cleans up event monitors.
    func deactivate() {
        guard isActive else { return }
        isActive = false

        // Hide all overlays
        for overlay in overlays.values {
            overlay.deactivate()
        }

        matches = []
        labelMap = [:]
        removeEventMonitors()
        delegate?.hintsControllerDidDismiss(self)
    }

    // MARK: - Overlay Management

    /// Returns or creates a hints overlay for the given session.
    private func ensureOverlay(
        for session: TerminalSession
    ) -> TerminalHintsOverlayView {
        if let existing = overlays[session.id] {
            // Ensure overlay is on the correct terminal view
            if existing.superview !== session.terminalView {
                existing.removeFromSuperview()
                existing.frame = session.terminalView.bounds
                session.terminalView.addSubview(existing)
            }
            return existing
        }

        let overlay = TerminalHintsOverlayView(frame: session.terminalView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        session.terminalView.addSubview(overlay)
        overlays[session.id] = overlay
        return overlay
    }

    // MARK: - Event Monitoring

    /// Installs keyboard and mouse monitors to capture input during hints mode.
    /// All key events are consumed to prevent input from reaching the PTY.
    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isActive else { return event }
            self.handleKeyDown(event)
            return nil // Consume all key events during hints mode
        }

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self, self.isActive else { return event }
            self.deactivate()
            return event // Pass click through after dismissing
        }
    }

    /// Removes event monitors on deactivation or cleanup.
    private func removeEventMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Key Handling

    /// Processes a key event during hints mode.
    /// Escape dismisses. Letter keys trigger actions on matching hints.
    private func handleKeyDown(_ event: NSEvent) {
        // Escape dismisses
        if event.keyCode == 53 {
            deactivate()
            return
        }

        // Get the typed character(s) — lowercase for label matching
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              !chars.isEmpty else {
            deactivate()
            return
        }

        // Check for two-letter label prefix: if the typed character starts a multi-char
        // label, wait for the second character. For simplicity in this implementation,
        // we check single-char labels first, then deactivate on no match.
        if let match = labelMap[chars] {
            let action = resolveAction(from: event)
            delegate?.hintsController(self, didSelect: match, action: action)
            deactivate()
            return
        }

        // No matching label — dismiss
        deactivate()
    }

    /// Determines the action based on modifier keys held during label selection.
    private func resolveAction(from event: NSEvent) -> HintAction {
        if event.modifierFlags.contains(.shift) {
            return .copy
        } else if event.modifierFlags.contains(.option) {
            return .insertAtCursor
        }
        return .defaultAction
    }

    // MARK: - Cleanup

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
    }
}
