// FileListTableView.swift
// Custom NSTableView subclass that intercepts key events for file navigation.
// Callbacks are set by the owning FilePanelViewController.

import AppKit

final class FileListTableView: NSTableView {

    // MARK: - Key Event Callbacks

    var onEnter: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onFunctionKey: ((_ keyNumber: Int) -> Void)?
    var onPaste: (() -> Void)?

    /// FAYT: called when an alphanumeric character is typed, activating filter mode.
    /// The string contains the typed character to forward to the breadcrumb edit field.
    var onTypingActivation: ((_ character: String) -> Void)?

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) >= 0 {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return / Enter
            onEnter?()
        case 51: // Backspace / Delete
            onBackspace?()
        case 96:  // F5
            onFunctionKey?(5)
        case 97:  // F6
            onFunctionKey?(6)
        case 98:  // F7
            onFunctionKey?(7)
        case 100: // F8
            onFunctionKey?(8)
        case 9: // V key
            if event.modifierFlags.contains(.command) {
                onPaste?()
                return
            }
            fallthrough
        default:
            // FAYT: intercept alphanumeric characters to activate filter mode
            if let chars = event.characters,
               !chars.isEmpty,
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control),
               chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                onTypingActivation?(chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
