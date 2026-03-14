// OnboardingWelcomeViewController.swift
// First screen of the onboarding flow — shown before permissions.
// Two-column layout matching the permissions screen:
//   Left:  "Step 1" badge, headline, subtitle
//   Right: Embedded video player with expand-to-full-window support
//
// An expand button overlaid on the video fills the entire window with the
// player. A close button in the top-right corner snaps back to the
// two-column layout.

import AppKit
import AVKit

@MainActor
final class OnboardingWelcomeViewController: NSViewController {

    // MARK: - Properties

    /// Called when the user clicks Continue to advance to the next step.
    var onContinue: (() -> Void)?

    private var playerView: AVPlayerView!
    private var expandButton: NSButton!

    /// Overlay that covers the entire view when the video is expanded.
    private var fullScreenOverlay: NSView?

    /// Saved window frame to restore when collapsing from expanded video.
    private var savedWindowFrame: NSRect?

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme
        let font = FontManager.shared.activeFont

        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        // --- Left Column ---
        let leftColumn = NSView()
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftColumn)

        // "Step 1" badge
        let badge = makeBadge("Step 1", theme: theme, font: font)
        leftColumn.addSubview(badge)

        // Headline
        let headline = NSTextField(labelWithString: "Welcome to\nSingle Pane")
        headline.maximumNumberOfLines = 2
        headline.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        headline.textColor = theme.chromeText
        headline.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addSubview(headline)

        // Subtitle
        let subtitle = NSTextField(wrappingLabelWithString:
            "Watch a quick overview to get the most out of the Single Pane experience."
        )
        subtitle.font = font.withSize(12)
        subtitle.textColor = theme.chromeTextSecondary
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addSubview(subtitle)

        NSLayoutConstraint.activate([
            leftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            leftColumn.topAnchor.constraint(equalTo: view.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftColumn.widthAnchor.constraint(equalToConstant: 240),

            badge.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            badge.topAnchor.constraint(equalTo: leftColumn.topAnchor, constant: 60),

            headline.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            headline.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            headline.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 16),

            subtitle.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 12),
        ])

        // --- Right Column (Video + Continue) ---
        let rightColumn = NSView()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightColumn)

        // Vertical separator
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = theme.chromeBorder.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        // Video container — holds the player and the expand button
        let videoContainer = NSView()
        videoContainer.wantsLayer = true
        videoContainer.layer?.cornerRadius = 8
        videoContainer.layer?.masksToBounds = true
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addSubview(videoContainer)

        // Video player
        playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.translatesAutoresizingMaskIntoConstraints = false

        if let videoURL = Bundle.main.url(forResource: "onboarding_placeholder", withExtension: "mp4") {
            playerView.player = AVPlayer(url: videoURL)
        }
        playerView.videoGravity = .resizeAspectFill
        videoContainer.addSubview(playerView)

        // Expand button — overlaid on top-right of the video
        expandButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                           accessibilityDescription: "Expand video")!
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!,
            target: self,
            action: #selector(expandVideo)
        )
        expandButton.isBordered = false
        expandButton.wantsLayer = true
        expandButton.layer?.cornerRadius = 6
        expandButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        expandButton.contentTintColor = .white
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(expandButton)

        // Continue button — matches the permissions screen style
        let continueButton = NSButton(title: "", target: self, action: #selector(continueClicked))
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.keyEquivalent = "\r"
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        // Attributed title: "Continue  →"
        let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Continue")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let attachment = NSTextAttachment()
        attachment.image = arrow
        let attrTitle = NSMutableAttributedString(
            string: "Continue  ",
            attributes: [
                .font: font.withSize(14),
                .foregroundColor: NSColor.white,
            ]
        )
        attrTitle.append(NSAttributedString(attachment: attachment))
        continueButton.attributedTitle = attrTitle

        rightColumn.addSubview(continueButton)

        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),
            separator.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 24),

            rightColumn.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 24),
            rightColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            rightColumn.topAnchor.constraint(equalTo: view.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Video pinned to top of right column, 16:9 aspect ratio
            videoContainer.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            videoContainer.topAnchor.constraint(equalTo: rightColumn.topAnchor, constant: 40),
            videoContainer.heightAnchor.constraint(equalTo: videoContainer.widthAnchor, multiplier: 9.0 / 16.0),

            // Player fills its container
            playerView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),

            // Expand button pinned to top-right of video
            expandButton.topAnchor.constraint(equalTo: videoContainer.topAnchor, constant: 8),
            expandButton.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -8),
            expandButton.widthAnchor.constraint(equalToConstant: 28),
            expandButton.heightAnchor.constraint(equalToConstant: 28),

            continueButton.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            continueButton.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Badge

    /// Creates a small colored pill label (e.g., "Step 1").
    private func makeBadge(_ text: String, theme: Theme, font: NSFont) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = theme.hookGreen.withAlphaComponent(0.2).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = NSFontManager.shared.convert(font.withSize(10), toHaveTrait: .boldFontMask)
        label.textColor = theme.hookGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
        ])

        return container
    }

    // MARK: - Full-Screen Video

    /// Expands the video to fill a larger window with a close button overlay.
    @objc private func expandVideo() {
        guard fullScreenOverlay == nil, let window = view.window else { return }

        let theme = ThemeManager.shared.activeTheme

        // Save the current window frame so we can restore it on collapse
        savedWindowFrame = window.frame

        // Resize window to 1200px wide, keeping it centered
        let expandedWidth: CGFloat = 1200
        let expandedHeight: CGFloat = 720
        let newOrigin = NSPoint(
            x: window.frame.midX - expandedWidth / 2,
            y: window.frame.midY - expandedHeight / 2
        )
        let expandedFrame = NSRect(origin: newOrigin, size: NSSize(width: expandedWidth, height: expandedHeight))
        window.setFrame(expandedFrame, display: true, animate: true)

        // Dark overlay that covers the entire view
        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = theme.chromeBackground.cgColor
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        fullScreenOverlay = overlay

        // Full-screen player view sharing the same player instance
        let fullPlayer = AVPlayerView()
        fullPlayer.controlsStyle = .inline
        fullPlayer.videoGravity = .resizeAspectFill
        fullPlayer.player = playerView.player
        fullPlayer.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(fullPlayer)

        // Close button — top-right corner
        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark",
                           accessibilityDescription: "Close full screen")!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .bold))!,
            target: self,
            action: #selector(collapseVideo)
        )
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 14
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        closeButton.contentTintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(closeButton)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Player fills the overlay edge-to-edge — no black bars
            fullPlayer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            fullPlayer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            fullPlayer.topAnchor.constraint(equalTo: overlay.topAnchor),
            fullPlayer.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    /// Collapses the expanded overlay and restores the original window size.
    @objc private func collapseVideo() {
        fullScreenOverlay?.removeFromSuperview()
        fullScreenOverlay = nil

        // Restore the original window frame
        if let savedFrame = savedWindowFrame, let window = view.window {
            window.setFrame(savedFrame, display: true, animate: true)
            savedWindowFrame = nil
        }
    }

    // MARK: - Actions

    @objc private func continueClicked() {
        collapseVideo()
        playerView.player?.pause()
        onContinue?()
    }
}
