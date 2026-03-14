// MainWindowController.swift
// Single-window controller with frame autosave.
// Launches maximized to fill the screen. Minimum 800x500.

import AppKit

@MainActor
final class MainWindowController: NSWindowController {

    convenience init(contentViewController: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SinglePane"
        window.minSize = NSSize(width: 800, height: 500)
        window.setFrameAutosaveName("MainWindow")
        window.contentViewController = contentViewController

        // Maximize to fill the screen on launch
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }

        self.init(window: window)
    }
}
