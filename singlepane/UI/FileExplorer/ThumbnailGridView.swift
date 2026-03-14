// ThumbnailGridView.swift
// NSCollectionView-based thumbnail grid for the file panel.
// Displays file thumbnails in a flow layout grid with hover filename overlay.
// Supports drag/drop, keyboard navigation, FAYT, and context menus.

import AppKit
import QuickLookThumbnailing

// MARK: - ThumbnailGridView

/// Custom NSCollectionView subclass that intercepts key events for file navigation.
/// Mirrors FileListTableView's keyboard handling for consistency.
final class ThumbnailGridView: NSCollectionView {

    // MARK: - Key Event Callbacks

    var onEnter: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onPaste: (() -> Void)?
    var onTypingActivation: ((_ character: String) -> Void)?
    var onDoubleClick: (() -> Void)?

    // MARK: - Double Click

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return / Enter
            onEnter?()
        case 51: // Backspace / Delete
            onBackspace?()
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

// MARK: - ThumbnailGridItem

/// A single cell in the thumbnail grid.
/// Shows a thumbnail image centered in the cell, with a hover overlay for the filename.
final class ThumbnailGridItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailGridItem")

    /// The file item this cell represents.
    var fileItem: FileItem?

    /// Thumbnail image view filling the cell.
    private let thumbnailImageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 4
        iv.layer?.masksToBounds = true
        return iv
    }()

    /// Hover overlay label showing the filename.
    private let nameLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.alignment = .center
        tf.lineBreakMode = .byTruncatingMiddle
        tf.maximumNumberOfLines = 2
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isHidden = true
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 3
        tf.layer?.masksToBounds = true
        return tf
    }()

    /// Background view for selection highlight.
    private let selectionBox: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    /// Tracking area for hover detection.
    private var trackingArea: NSTrackingArea?

    /// Pre-built folder SF Symbol (shared across all items).
    private static let folderImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        return NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: "Folder"
        )?.withSymbolConfiguration(config)
    }()

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        container.addSubview(selectionBox)
        container.addSubview(thumbnailImageView)
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            // Selection box fills the cell
            selectionBox.topAnchor.constraint(equalTo: container.topAnchor),
            selectionBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            selectionBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Thumbnail inset from cell edges
            thumbnailImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            thumbnailImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            thumbnailImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            thumbnailImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),

            // Name label pinned to bottom of cell
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        self.view = container
    }

    override var isSelected: Bool {
        didSet {
            selectionBox.isHidden = !isSelected
        }
    }

    // MARK: - Configuration

    /// Configures the cell with a file item. Loads thumbnail asynchronously.
    func configure(with item: FileItem, thumbnailSize: ThumbnailSize) {
        fileItem = item

        // Hidden files at 50% opacity
        let alpha: CGFloat = item.isHidden ? 0.5 : 1.0
        thumbnailImageView.alphaValue = alpha
        nameLabel.alphaValue = alpha

        nameLabel.stringValue = item.name
        nameLabel.isHidden = true

        let theme = ThemeManager.shared.activeTheme
        nameLabel.backgroundColor = theme.explorerBackground.withAlphaComponent(0.85)
        nameLabel.textColor = theme.explorerText
        nameLabel.font = FontManager.shared.activeFont.withSize(10)
        selectionBox.layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.15).cgColor

        if item.isDirectory {
            // Folders use tinted SF Symbol
            thumbnailImageView.image = Self.folderImage
            thumbnailImageView.contentTintColor = theme.chromeAccent.withAlphaComponent(0.7)
        } else {
            // Show file-type icon as placeholder, load real thumbnail async
            thumbnailImageView.contentTintColor = nil
            thumbnailImageView.image = NSWorkspace.shared.icon(forFile: item.url.path)

            let url = item.url
            let size = thumbnailSize
            Task {
                let thumbnail = await ThumbnailService.shared.thumbnail(for: url, size: size)
                // Verify this cell still shows the same file (reuse guard)
                guard self.fileItem?.url == url else { return }
                await MainActor.run {
                    self.thumbnailImageView.image = thumbnail
                }
            }
        }
    }

    // MARK: - Hover Tracking

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        nameLabel.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        nameLabel.isHidden = true
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
        thumbnailImageView.contentTintColor = nil
        thumbnailImageView.alphaValue = 1.0
        nameLabel.isHidden = true
        nameLabel.stringValue = ""
        selectionBox.isHidden = true
        fileItem = nil
    }
}
