// HotkeyToggleView.swift
// Inline clickable hotkey area for layout rows in the Layout Manager popover.
// Three states: unbound ("Record"), recording ("Press combo..."), bound (pill display).
// Click toggles: unbound → recording, bound → clears hotkey.
// Escape cancels recording. Validation errors shown briefly inline.

import AppKit

@MainActor
final class HotkeyToggleView: NSView {

    // MARK: - State

    /// The layout identifier this toggle manages hotkeys for.
    private let layoutID: String

    /// Whether the view is actively capturing a keypress.
    private var isRecording = false {
        didSet { updateDisplay() }
    }

    /// Brief error message shown after invalid key combo.
    private var errorMessage: String?

    /// Timer to auto-clear error messages.
    private var errorTimer: Timer?

    /// Called when the hotkey binding changes (set or cleared).
    var onHotkeyChanged: (() -> Void)?

    // MARK: - UI Elements

    private let label = NSTextField(labelWithString: "")

    // MARK: - Constants

    private static let pillHeight: CGFloat = 16
    private static let minWidth: CGFloat = 70
    private static let cornerRadius: CGFloat = 4
    private static let errorDuration: TimeInterval = 2.0

    // MARK: - Init

    init(layoutID: String) {
        self.layoutID = layoutID
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.pillHeight))
        wantsLayer = true
        setupLabel()
        updateDisplay()

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupLabel() {
        label.alignment = .center
        label.font = FontManager.shared.activeFont.withSize(9)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.minWidth, height: Self.pillHeight)
    }

    // MARK: - Display

    /// Updates the label text and appearance based on current state.
    private func updateDisplay() {
        let theme = ThemeManager.shared.activeTheme

        if let error = errorMessage {
            // Error state — red text
            label.stringValue = error
            label.textColor = theme.hookRed
            layer?.backgroundColor = theme.hookRed.withAlphaComponent(0.1).cgColor
        } else if isRecording {
            // Recording state — pulsing prompt
            label.stringValue = "Press combo..."
            label.textColor = theme.chromeAccent
            layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.1).cgColor
        } else if let binding = LayoutHotkeyManager.shared.hotkey(for: layoutID) {
            // Bound state — show hotkey pill
            label.stringValue = binding.displayString
            label.textColor = theme.chromeText
            layer?.backgroundColor = theme.chromeTextSecondary.withAlphaComponent(0.15).cgColor
        } else {
            // Unbound state — dim "Record" prompt
            label.stringValue = "Record"
            label.textColor = theme.chromeTextSecondary.withAlphaComponent(0.5)
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        layer?.cornerRadius = Self.cornerRadius
    }

    // MARK: - Key Capture

    /// Accept first responder so we can receive keyDown events during recording.
    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let binding = HotkeyBinding(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        let result = LayoutHotkeyManager.shared.validate(binding: binding, for: layoutID)

        switch result {
        case .valid:
            LayoutHotkeyManager.shared.setHotkey(for: layoutID, binding: binding)
            isRecording = false
            window?.makeFirstResponder(nil)
            onHotkeyChanged?()

        case .dangerous(let reason):
            showError(reason)

        case .conflict(let existingID):
            let name = LayoutHotkeyManager.shared.displayName(for: existingID)
            showError("Used by \"\(name)\"")
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            // Click while recording → cancel
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        if LayoutHotkeyManager.shared.hasHotkey(for: layoutID) {
            // Bound → clear the hotkey
            LayoutHotkeyManager.shared.removeHotkey(for: layoutID)
            updateDisplay()
            onHotkeyChanged?()
        } else {
            // Unbound → start recording
            isRecording = true
            window?.makeFirstResponder(self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Error Display

    /// Shows an error message briefly, then restores normal display.
    private func showError(_ message: String) {
        errorTimer?.invalidate()
        errorMessage = message
        updateDisplay()

        errorTimer = Timer.scheduledTimer(withTimeInterval: Self.errorDuration, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                self?.errorMessage = nil
                self?.updateDisplay()
            }
        }
    }

    // MARK: - Resign

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
        }
        return super.resignFirstResponder()
    }
}
