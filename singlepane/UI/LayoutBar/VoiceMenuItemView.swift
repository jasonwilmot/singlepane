// VoiceMenuItemView.swift
// Custom NSView used as an NSMenuItem's view in the voice picker menu.
// Shows a play-preview button, the voice name, and an optional gear icon for custom packs.
// Clicking the play button previews the voice; clicking the name selects it;
// clicking the gear opens the custom pack editor.

import AppKit

@MainActor
final class VoiceMenuItemView: NSView {

    // MARK: - Properties

    private let voicePack: VoicePack
    private let onSelect: (String) -> Void
    private let onPreview: (String) -> Void
    private let onEdit: ((String) -> Void)?

    private let isSelected: Bool
    private let playButton = NSButton()
    private let nameLabel = NSTextField(labelWithString: "")
    private var gearButton: NSButton?

    // MARK: - Init

    init(
        voicePack: VoicePack,
        isSelected: Bool,
        onSelect: @escaping (String) -> Void,
        onPreview: @escaping (String) -> Void,
        onEdit: ((String) -> Void)? = nil
    ) {
        self.voicePack = voicePack
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPreview = onPreview
        self.onEdit = onEdit
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        setupViews(isSelected: isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews(isSelected: Bool) {
        let theme = ThemeManager.shared.activeTheme
        wantsLayer = true

        // Highlight the selected row with a subtle background
        if isSelected {
            layer?.backgroundColor = theme.chromeText.withAlphaComponent(0.12).cgColor
        }

        // Preview button — waveform icon for sound packs, play icon for voices
        let iconName = voicePack.isSoundPack ? "waveform" : "play.fill"
        let iconLabel = voicePack.isSoundPack ? "Preview sound" : "Preview voice"
        playButton.bezelStyle = .inline
        playButton.isBordered = false
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [theme.chromeText])
        let symbolImage = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: iconLabel
        )?.withSymbolConfiguration(sizeConfig.applying(colorConfig))
        playButton.image = symbolImage
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = theme.chromeText
        playButton.target = self
        playButton.action = #selector(playClicked)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playButton)

        // Voice name label
        nameLabel.stringValue = voicePack.displayName
        nameLabel.font = FontManager.shared.activeFont.withSize(11)
        nameLabel.textColor = theme.chromeText
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        // Gear button — shown for all packs (mute hooks for bundled, full edit for custom)
        let trailingAnchorForLabel: NSLayoutXAxisAnchor
        if onEdit != nil {
            let gear = NSButton()
            gear.bezelStyle = .inline
            gear.isBordered = false
            gear.image = NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: "Edit custom pack"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
            )
            gear.imagePosition = .imageOnly
            gear.contentTintColor = theme.chromeTextSecondary
            gear.target = self
            gear.action = #selector(gearClicked)
            gear.translatesAutoresizingMaskIntoConstraints = false
            addSubview(gear)
            gearButton = gear

            NSLayoutConstraint.activate([
                gear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                gear.centerYAnchor.constraint(equalTo: centerYAnchor),
                gear.widthAnchor.constraint(equalToConstant: 18),
                gear.heightAnchor.constraint(equalToConstant: 18),
            ])
            trailingAnchorForLabel = gear.leadingAnchor
        } else {
            trailingAnchorForLabel = trailingAnchor
        }

        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 18),
            playButton.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorForLabel, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func playClicked() {
        onPreview(voicePack.directoryName)
    }

    @objc private func gearClicked() {
        onEdit?(voicePack.directoryName)
    }

    /// Clicking anywhere except the play/gear buttons selects this voice.
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let playFrame = playButton.frame.insetBy(dx: -4, dy: -4)
        if playFrame.contains(location) { return }
        if let gear = gearButton {
            let gearFrame = gear.frame.insetBy(dx: -4, dy: -4)
            if gearFrame.contains(location) { return }
        }
        onPreview(voicePack.directoryName)
        onSelect(voicePack.directoryName)
    }

    /// Highlight on hover for visual feedback (layered on top of selected highlight).
    override func draw(_ dirtyRect: NSRect) {
        if isMouseInside && !isSelected {
            let theme = ThemeManager.shared.activeTheme
            theme.chromeText.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }

    /// Track mouse enter/exit for hover highlighting and pointing hand cursor.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    private var isMouseInside = false

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        needsDisplay = true
    }
}
