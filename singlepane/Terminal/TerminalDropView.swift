// TerminalDropView.swift
// NSView subclass that accepts file URL drags and inserts shell-escaped paths
// into the active terminal session. Used as the terminal content container.

import AppKit

@MainActor
final class TerminalDropView: NSView {

    /// Called with shell-escaped paths when non-directory files are dropped.
    var onFilesDropped: ((String) -> Void)?

    /// Called with the directory URL when a folder is dropped.
    var onFolderDropped: ((URL) -> Void)?

    /// Overlay view for hook-driven highlight color wash over the terminal pane.
    private var highlightOverlay: NSView?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    /// Snap autoresizing-mask subviews (the terminal view) to integer frame heights.
    /// SwiftTerm's cellHeight is always an integer (via ceil()), so integer frame heights
    /// ensure all row positions land on pixel boundaries, preventing sub-pixel line artifacts.
    override func layout() {
        super.layout()
        for subview in subviews where subview.translatesAutoresizingMaskIntoConstraints {
            var frame = subview.frame
            let snappedHeight = floor(frame.size.height)
            let snappedWidth = floor(frame.size.width)
            let changed = snappedHeight != frame.size.height || snappedWidth != frame.size.width
            frame.size.height = snappedHeight
            frame.size.width = snappedWidth
            subview.frame = frame
            if changed {
                subview.needsDisplay = true
            }
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }

        // Separate folders from files
        var folders: [URL] = []
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                folders.append(url)
            } else {
                files.append(url)
            }
        }

        // Folders → open new terminal tab at each directory
        for folder in folders {
            onFolderDropped?(folder)
        }

        // Files → insert escaped paths into active terminal
        if !files.isEmpty {
            let escapedPaths = files.map { Self.shellEscape($0.path) }.joined(separator: " ")
            onFilesDropped?(escapedPaths)
        }

        return !folders.isEmpty || !files.isEmpty
    }

    // MARK: - Highlight Overlay

    /// Applies a subtle color wash over the terminal pane to match the tab highlight.
    /// Pass nil to remove the overlay. Uses an NSView overlay that passes all mouse
    /// events through so it never interferes with terminal interaction.
    func setHighlightColor(_ color: NSColor?) {
        if let color {
            if highlightOverlay == nil {
                let overlay = HighlightOverlayView()
                overlay.translatesAutoresizingMaskIntoConstraints = false
                overlay.wantsLayer = true
                addSubview(overlay)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: topAnchor),
                    overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
                    overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                highlightOverlay = overlay
            }
            highlightOverlay?.layer?.backgroundColor = color.withAlphaComponent(0.06).cgColor
        } else {
            highlightOverlay?.removeFromSuperview()
            highlightOverlay = nil
        }
    }

    // MARK: - Highlight Overlay View

    /// Transparent overlay that passes all mouse events through to views beneath it.
    private final class HighlightOverlayView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    // MARK: - Shell Escaping

    /// Escape a file path for safe shell insertion.
    /// Uses single-quote wrapping which handles all special chars except single quotes.
    private static func shellEscape(_ path: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/-_."))
        if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return path
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
