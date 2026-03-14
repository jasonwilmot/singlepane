// PanelShiftArrowView.swift
// Compact left/right chevron buttons for swapping a panel with its neighbor.
// Embedded in each panel's tab bar row. Visibility is driven by ShiftArrowState.

import AppKit

@MainActor
final class PanelShiftArrowView: NSView {

    // MARK: - Properties

    /// The panel type this view represents. Used to call the delegate.
    let panelType: PanelType

    /// Delegate that handles the actual panel swap.
    weak var shiftDelegate: PanelShiftDelegate?

    private let leftButton = NSButton()
    private let rightButton = NSButton()

    /// Button size matching existing tab bar action buttons.
    private static let buttonSize: CGFloat = 24

    // MARK: - Init

    init(panelType: PanelType) {
        self.panelType = panelType
        super.init(frame: .zero)
        setupButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupButtons() {
        // Buttons are set up but kept permanently hidden — the swap infrastructure
        // remains wired so a future UI (e.g., layout bar, context menu) can trigger
        // panel reordering without re-plumbing delegates or state computation.
        for (button, symbolName, action) in [
            (leftButton, "chevron.compact.left", #selector(leftClicked)),
            (rightButton, "chevron.compact.right", #selector(rightClicked)),
        ] {
            button.bezelStyle = .accessoryBarAction
            button.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: symbolName.contains("left") ? "Shift left" : "Shift right"
            )
            button.imagePosition = .imageOnly
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isHidden = true
            addSubview(button)
        }

        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        // Zero-width so anchored neighbors collapse flush against the container edge.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 0),
            heightAnchor.constraint(equalToConstant: 0),
        ])
    }

    // MARK: - State Update

    /// Updates button visibility and tooltips from a computed state.
    /// Currently a no-op — arrows are hidden pending a redesigned trigger UI.
    /// The state is still tracked so the swap infrastructure stays warm.
    func update(_ state: ShiftArrowState) {
        // No-op: arrows hidden pending redesigned panel reorder UI.
    }

    // MARK: - Actions

    @objc private func leftClicked() {
        shiftDelegate?.shiftPanel(panelType, direction: .left)
    }

    @objc private func rightClicked() {
        shiftDelegate?.shiftPanel(panelType, direction: .right)
    }
}
