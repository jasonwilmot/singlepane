// TerminalSessionManager.swift
// Manages multiple terminal sessions (one per tab).
// Handles create, close, switch, and multi-session display for split views.
// View layout is managed by TerminalContainerViewController — this class tracks state only.

import AppKit

@MainActor
final class TerminalSessionManager {

    // MARK: - Properties

    private(set) var sessions: [TerminalSession] = []

    /// The focused session index — receives keyboard input in split mode.
    private(set) var focusedIndex: Int = 0

    /// Indices of all currently visible sessions. Single-element for normal view,
    /// multiple elements when terminal splits are active.
    private(set) var visibleIndices: Set<Int> = [0]

    /// The container view bounds used for initial session frame sizing.
    let containerView: NSView

    /// The focused session — receives keyboard input and find bar actions.
    var activeSession: TerminalSession? {
        guard sessions.indices.contains(focusedIndex) else { return nil }
        return sessions[focusedIndex]
    }

    /// All sessions currently visible in the split layout, in sorted index order.
    var visibleSessions: [TerminalSession] {
        visibleIndices.sorted().compactMap { idx in
            sessions.indices.contains(idx) ? sessions[idx] : nil
        }
    }

    // MARK: - Init

    init(containerView: NSView) {
        self.containerView = containerView
    }

    // MARK: - Session Management

    /// Create a new terminal session. Updates state only — caller handles view layout.
    @discardableResult
    func createSession(directory: String? = nil) -> TerminalSession {
        let session = TerminalSession(frame: containerView.bounds)
        sessions.append(session)
        let newIndex = sessions.count - 1
        focusedIndex = newIndex
        visibleIndices = [newIndex]
        session.startShell(currentDirectory: directory)
        return session
    }

    /// Switch to a single terminal session (collapses any split). State only.
    func switchTo(_ index: Int) {
        guard index >= 0, index < sessions.count else { return }
        focusedIndex = index
        visibleIndices = [index]
    }

    /// Display multiple sessions simultaneously. State only — caller builds the split view.
    func showMultiple(indices: Set<Int>) {
        let valid = indices.filter { sessions.indices.contains($0) }
        guard !valid.isEmpty else { return }
        visibleIndices = Set(valid)

        // Ensure focused index is among visible sessions
        if !visibleIndices.contains(focusedIndex) {
            focusedIndex = visibleIndices.sorted().first!
        }
    }

    /// Set the focused session within the visible set.
    func setFocused(index: Int) {
        guard visibleIndices.contains(index) else { return }
        focusedIndex = index
    }

    /// Re-applies the active theme to all terminal sessions.
    func applyThemeToAllSessions() {
        for session in sessions {
            session.applyTheme()
        }
    }

    /// Re-applies the active font to all terminal sessions.
    func applyFontToAllSessions() {
        for session in sessions {
            session.applyFont()
        }
    }

    /// Moves a session from one index to another. State only — caller handles view rebuild.
    /// Used by drag-to-reorder to rearrange the sessions array and remap indices.
    func moveSession(from oldIndex: Int, to newIndex: Int) {
        guard oldIndex != newIndex,
              sessions.indices.contains(oldIndex),
              newIndex >= 0, newIndex < sessions.count else { return }

        let session = sessions.remove(at: oldIndex)
        sessions.insert(session, at: newIndex)

        // Remap focused index to follow the moved session
        if focusedIndex == oldIndex {
            focusedIndex = newIndex
        } else if oldIndex < focusedIndex && newIndex >= focusedIndex {
            focusedIndex -= 1
        } else if oldIndex > focusedIndex && newIndex <= focusedIndex {
            focusedIndex += 1
        }

        // Remap visible indices — rebuild from scratch since positions shifted
        if visibleIndices.count > 1 {
            visibleIndices = Set(0..<sessions.count)
        } else {
            visibleIndices = [focusedIndex]
        }
    }

    /// Close the session at the given index. State only — caller handles view teardown.
    func closeSession(at index: Int) {
        guard sessions.count > 1, index < sessions.count else { return }

        let session = sessions.remove(at: index)
        session.terminalView.removeFromSuperview()

        // Remap visible indices after removal
        var remapped: Set<Int> = []
        for idx in visibleIndices {
            if idx == index { continue }
            remapped.insert(idx > index ? idx - 1 : idx)
        }
        if remapped.isEmpty {
            remapped = [min(index, sessions.count - 1)]
        }
        visibleIndices = remapped

        // Adjust focused index
        if focusedIndex == index {
            focusedIndex = visibleIndices.sorted().first!
        } else if focusedIndex > index {
            focusedIndex -= 1
        }
    }
}
