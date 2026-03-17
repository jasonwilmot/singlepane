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
        window.contentViewController = contentViewController

        // Restore saved frame if one exists, otherwise maximize on first launch.
        // setFrameAutosaveName must come after contentViewController is set so
        // Auto Layout constraints are in place before frame restoration.
        let hasAutoSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame MainWindow") != nil
        window.setFrameAutosaveName("MainWindow")
        if !hasAutoSavedFrame, let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }

        self.init(window: window)
    }
}
