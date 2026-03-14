// MediaPlayerViewController.swift
// Plays audio and video files using AVPlayerView with native transport controls.

import AppKit
import AVKit
import AVFoundation

@MainActor
final class MediaPlayerViewController: NSViewController {

    // MARK: - Properties

    private let playerView = AVPlayerView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private var player: AVPlayer?

    /// The file currently being played.
    private(set) var currentFileURL: URL?

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        filenameLabel.alignment = .center
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(filenameLabel)

        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        // Prevent AVPlayerView from influencing the split pane width
        playerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        playerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)

        NSLayoutConstraint.activate([
            filenameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            filenameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            filenameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            playerView.topAnchor.constraint(equalTo: filenameLabel.bottomAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    override var view: NSView {
        get { super.view }
        set {
            // Prevent intrinsic content size from propagating to the split view
            newValue.setContentHuggingPriority(.defaultLow, for: .horizontal)
            newValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            super.view = newValue
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        startObservingTheme()
    }

    // MARK: - Loading

    func loadMedia(at url: URL) {
        _ = self.view
        currentFileURL = url

        // Stop any existing playback
        player?.pause()

        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
            playerView.player = player
        } else {
            player?.replaceCurrentItem(with: item)
        }

        filenameLabel.stringValue = url.lastPathComponent
        player?.play()
    }

    /// Stop playback and release resources.
    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        currentFileURL = nil
        filenameLabel.stringValue = ""
    }

    // MARK: - Theme

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        filenameLabel.textColor = theme.chromeTextSecondary
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.explorerBackground.cgColor
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
}
