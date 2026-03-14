// HotkeyRecorderPopoverViewController.swift
// Small popover content for recording and managing layout hotkey bindings.
// Two states: "no hotkey" shows a Record button; "has hotkey" shows the combo + Delete Hotkey.
// For custom layouts, an additional "Delete Layout" button is shown.
// Key combos auto-save on press. Dangerous/conflicting combos show inline errors.

import AppKit

@MainActor
final class HotkeyRecorderPopoverViewController: NSViewController {

    // MARK: - Properties

    /// The layout identifier (SnapLayout rawValue or CustomLayout UUID string).
    private let layoutID: String

    /// Called when the hotkey state changes so the icon view can redraw its border.
    var onHotkeyChanged: (() -> Void)?

    /// Called when the user clicks "Delete Layout". Only set for custom layouts.
    var onDeleteLayout: (() -> Void)?

    /// Whether we are actively listening for the next key combo.
    private var isRecording = false

    /// Local event monitor that intercepts key events before AppKit dispatch.
    /// Required because Cmd-based shortcuts route through performKeyEquivalent
    /// (menus, views) before keyDown, so keyDown never fires for them.
    nonisolated(unsafe) private var keyMonitor: Any?

    // MARK: - UI Elements

    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(frame: .zero)
    private let deleteHotkeyButton = NSButton(frame: .zero)
    private let deleteLayoutButton = NSButton(frame: .zero)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let containerStack = NSStackView()

    // MARK: - Constants

    private static let popoverWidth: CGFloat = 180
    private static let padding: CGFloat = 12

    // MARK: - Init

    init(layoutID: String) {
        self.layoutID = layoutID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Setup

    override func loadView() {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        // Vertical stack: [hotkeyLabel] [recordButton] [deleteHotkeyButton] [errorLabel] [deleteLayoutButton]
        containerStack.orientation = .vertical
        containerStack.alignment = .centerX
        containerStack.spacing = 8
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(containerStack)

        // Hotkey display label — shows the current key combo or recording state
        hotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        hotkeyLabel.alignment = .center
        hotkeyLabel.textColor = ThemeManager.shared.activeTheme.chromeText
        containerStack.addArrangedSubview(hotkeyLabel)

        // Record button — starts key capture mode
        recordButton.bezelStyle = .inline
        recordButton.title = "Record Hotkey"
        recordButton.font = FontManager.shared.activeFont.withSize(11)
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        containerStack.addArrangedSubview(recordButton)

        // Delete hotkey button — removes the current hotkey binding
        deleteHotkeyButton.bezelStyle = .inline
        deleteHotkeyButton.title = "Delete Hotkey"
        deleteHotkeyButton.contentTintColor = ThemeManager.shared.activeTheme.hookRed
        deleteHotkeyButton.font = FontManager.shared.activeFont.withSize(11)
        deleteHotkeyButton.target = self
        deleteHotkeyButton.action = #selector(deleteHotkeyClicked)
        containerStack.addArrangedSubview(deleteHotkeyButton)

        // Error label — shown when a combo is blocked or conflicts
        errorLabel.font = FontManager.shared.activeFont.withSize(10)
        errorLabel.textColor = ThemeManager.shared.activeTheme.hookRed
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        errorLabel.maximumNumberOfLines = 2
        errorLabel.preferredMaxLayoutWidth = Self.popoverWidth - Self.padding * 2
        containerStack.addArrangedSubview(errorLabel)

        // Delete layout button — only for custom layouts, always visible at bottom
        deleteLayoutButton.bezelStyle = .inline
        deleteLayoutButton.title = "Delete Layout"
        deleteLayoutButton.contentTintColor = ThemeManager.shared.activeTheme.hookRed
        deleteLayoutButton.font = FontManager.shared.activeFont.withSize(11)
        deleteLayoutButton.target = self
        deleteLayoutButton.action = #selector(deleteLayoutClicked)
        deleteLayoutButton.isHidden = true // shown only when onDeleteLayout is set
        containerStack.addArrangedSubview(deleteLayoutButton)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: Self.padding),
            containerStack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -Self.padding),
            containerStack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Self.padding),
            containerStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -Self.padding),
            wrapper.widthAnchor.constraint(equalToConstant: Self.popoverWidth),
        ])

        self.view = wrapper
        updateUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Show delete layout button if a callback is provided (custom layouts only)
        deleteLayoutButton.isHidden = (onDeleteLayout == nil)
    }

    // MARK: - UI State

    /// Updates visibility of labels/buttons based on current hotkey state and recording mode.
    private func updateUI() {
        let binding = LayoutHotkeyManager.shared.hotkey(for: layoutID)

        if isRecording {
            hotkeyLabel.stringValue = "Press a key combo..."
            hotkeyLabel.textColor = ThemeManager.shared.activeTheme.chromeTextSecondary
            hotkeyLabel.isHidden = false
            recordButton.isHidden = true
            deleteHotkeyButton.isHidden = true
        } else if let binding {
            hotkeyLabel.stringValue = binding.displayString
            hotkeyLabel.textColor = ThemeManager.shared.activeTheme.chromeText
            hotkeyLabel.isHidden = false
            recordButton.title = "Change"
            recordButton.isHidden = false
            deleteHotkeyButton.isHidden = false
        } else {
            hotkeyLabel.isHidden = true
            recordButton.title = "Record Hotkey"
            recordButton.isHidden = false
            deleteHotkeyButton.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func recordButtonClicked() {
        isRecording = true
        errorLabel.isHidden = true
        updateUI()
        installKeyMonitor()
    }

    @objc private func deleteHotkeyClicked() {
        LayoutHotkeyManager.shared.removeHotkey(for: layoutID)
        isRecording = false
        errorLabel.isHidden = true
        updateUI()
        onHotkeyChanged?()
    }

    @objc private func deleteLayoutClicked() {
        onDeleteLayout?()
    }

    // MARK: - Key Capture

    /// Installs a local event monitor to capture key events during recording.
    /// This intercepts before AppKit's performKeyEquivalent dispatch, which
    /// is necessary because Cmd-based shortcuts never reach keyDown.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isRecording else { return event }

            // Escape cancels recording
            if event.keyCode == 53 {
                self.isRecording = false
                self.errorLabel.isHidden = true
                self.updateUI()
                self.removeKeyMonitor()
                return nil
            }

            let binding = HotkeyBinding(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            let result = LayoutHotkeyManager.shared.validate(binding: binding, for: self.layoutID)

            switch result {
            case .valid:
                LayoutHotkeyManager.shared.setHotkey(for: self.layoutID, binding: binding)
                self.isRecording = false
                self.errorLabel.isHidden = true
                self.updateUI()
                self.removeKeyMonitor()
                self.onHotkeyChanged?()

            case .dangerous(let reason):
                self.errorLabel.stringValue = reason
                self.errorLabel.isHidden = false

            case .conflict(let existingID):
                let name = LayoutHotkeyManager.shared.displayName(for: existingID)
                self.errorLabel.stringValue = "Already assigned to \"\(name)\""
                self.errorLabel.isHidden = false
            }

            return nil // Consume the event during recording
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
