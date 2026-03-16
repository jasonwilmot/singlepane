// PreviewZoomControlsView.swift
// Floating zoom controls overlay for the preview panel.
// Shown in the bottom-right corner when viewing images or PDFs.
//
// Layout:  [ - ]  100%  [ + ]  [ Fit ]
//
// Auto-fades after 3 seconds of inactivity; reappears on hover or zoom change.
// Styled with theme-derived colors and rounded corners.

import AppKit

// MARK: - Delegate

/// Communicates zoom control actions to the preview container.
@MainActor
protocol PreviewZoomControlsDelegate: AnyObject {
    func zoomControlsDidZoomIn()
    func zoomControlsDidZoomOut()
    func zoomControlsDidResetZoom()
    func zoomControlsDidZoomToActualSize()
}

// MARK: - View

@MainActor
final class PreviewZoomControlsView: NSView {

    weak var delegate: PreviewZoomControlsDelegate?

    /// How long to wait after the last interaction before fading out.
    private static let fadeDelay: TimeInterval = 3.0

    /// Duration of the fade animation.
    private static let fadeDuration: TimeInterval = 0.2

    // MARK: - Controls

    private let zoomOutButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(
            systemSymbolName: "minus",
            accessibilityDescription: "Zoom Out"
        )
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let zoomLabel: NSTextField = {
        let label = NSTextField(labelWithString: "100%")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private let zoomInButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "Zoom In"
        )
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    private let fitButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Fit to Window"
        )
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    /// Horizontal stack holding all controls.
    private let stack: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .horizontal
        sv.spacing = 4
        sv.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// Timer that fires to fade out the controls after inactivity.
    private var fadeTimer: Timer?

    /// Tracking area for mouse hover detection.
    private var hoverTrackingArea: NSTrackingArea?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayout()
        applyTheme()
        applyFont()
        startObservingTheme()
        startObservingFont()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func setupLayout() {
        wantsLayer = true
        layer?.cornerRadius = 6

        // Wire button targets
        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOutClicked)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomInClicked)
        fitButton.target = self
        fitButton.action = #selector(fitClicked)

        stack.addArrangedSubview(zoomOutButton)
        stack.addArrangedSubview(zoomLabel)
        stack.addArrangedSubview(zoomInButton)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(fitButton)

        // Extra gap between + and the separator
        stack.setCustomSpacing(8, after: zoomInButton)

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 18),
        ])
        return sep
    }

    // MARK: - Public

    /// Updates the zoom percentage label and restarts the auto-fade timer.
    func updateZoomLevel(_ percentage: Int) {
        zoomLabel.stringValue = "\(percentage)%"
        showAndRestartFadeTimer()
    }

    // MARK: - Hover & Fade

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // Cancel fade while hovering
        fadeTimer?.invalidate()
        fadeTimer = nil
        animator().alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        restartFadeTimer()
    }

    /// Shows the controls at full opacity and schedules a fade-out.
    func showAndRestartFadeTimer() {
        animator().alphaValue = 1.0
        restartFadeTimer()
    }

    private func restartFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.fadeDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeDuration
                    self?.animator().alphaValue = 0.3
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func zoomOutClicked() {
        delegate?.zoomControlsDidZoomOut()
    }

    @objc private func zoomInClicked() {
        delegate?.zoomControlsDidZoomIn()
    }

    @objc private func fitClicked() {
        delegate?.zoomControlsDidResetZoom()
    }

    // MARK: - Theme

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = theme.chromeBackground.withAlphaComponent(0.85).cgColor
        zoomLabel.textColor = theme.chromeTextSecondary
        zoomOutButton.contentTintColor = theme.chromeTextSecondary
        zoomInButton.contentTintColor = theme.chromeTextSecondary
        fitButton.contentTintColor = theme.chromeTextSecondary
    }

    private func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.startObservingTheme()
            }
        }
    }

    // MARK: - Font

    private func applyFont() {
        let font = FontManager.shared.activeFont
        let labelFont = NSFont(descriptor: font.fontDescriptor, size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        zoomLabel.font = labelFont

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        zoomOutButton.image = NSImage(
            systemSymbolName: "minus", accessibilityDescription: "Zoom Out"
        )?.withSymbolConfiguration(symbolConfig)
        zoomInButton.image = NSImage(
            systemSymbolName: "plus", accessibilityDescription: "Zoom In"
        )?.withSymbolConfiguration(symbolConfig)
        fitButton.image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Fit to Window"
        )?.withSymbolConfiguration(symbolConfig)
    }

    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.startObservingFont()
            }
        }
    }
}
