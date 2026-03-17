// BriefColumnView.swift
// Total Commander-style "Brief" view mode for the file panel.
// Shows only file/folder icons and names in a multi-column newspaper layout
// (top→bottom, left→right). No metadata. Maximum information density.
// Includes the NSCollectionView subclass, custom layout, and cell item.

import AppKit

// MARK: - BriefColumnView

/// Custom NSCollectionView subclass that intercepts key events for file navigation.
/// Mirrors FileListTableView and ThumbnailGridView keyboard handling for consistency.
final class BriefColumnView: NSCollectionView {

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

// MARK: - BriefColumnLayout

/// Custom NSCollectionViewLayout that arranges items in newspaper-style columns:
/// items flow top→bottom within each column, then left→right to the next column.
/// Column width is fixed at 200pt; column count adapts to the collection view width.
final class BriefColumnLayout: NSCollectionViewLayout {

    /// Fixed width for each column in points.
    static let columnWidth: CGFloat = 200

    /// Fixed height for each row in points (matches list view row height).
    static let rowHeight: CGFloat = 22

    /// Cached layout attributes for all items.
    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []

    /// Cached content size computed during prepare().
    private var contentSize: NSSize = .zero

    // MARK: - Layout Computation

    override func prepare() {
        super.prepare()
        cachedAttributes.removeAll()

        guard let collectionView else { return }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            contentSize = .zero
            return
        }

        let viewWidth = collectionView.bounds.width
        let columnCount = max(1, Int(floor(viewWidth / Self.columnWidth)))
        let columnWidth = viewWidth / CGFloat(columnCount)
        let viewHeight = collectionView.bounds.height
        let rowsPerColumn = max(1, Int(floor(viewHeight / Self.rowHeight)))

        for index in 0..<itemCount {
            let column = index / rowsPerColumn
            let row = index % rowsPerColumn

            let x = CGFloat(column) * columnWidth
            let y = CGFloat(row) * Self.rowHeight

            let indexPath = IndexPath(item: index, section: 0)
            let attrs = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attrs.frame = NSRect(x: x, y: y, width: columnWidth, height: Self.rowHeight)
            cachedAttributes.append(attrs)
        }

        // Content width extends beyond visible bounds if items overflow
        let totalColumns = itemCount > 0
            ? ((itemCount - 1) / rowsPerColumn) + 1
            : 0
        let contentWidth = max(viewWidth, CGFloat(totalColumns) * columnWidth)
        let contentHeight = CGFloat(min(itemCount, rowsPerColumn)) * Self.rowHeight
        contentSize = NSSize(width: contentWidth, height: max(viewHeight, contentHeight))
    }

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cachedAttributes.count else { return nil }
        return cachedAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return true }
        // Re-layout when width or height changes (column count or rows-per-column may change)
        return collectionView.bounds.size != newBounds.size
    }
}

// MARK: - BriefColumnItem

/// A single cell in the brief column view.
/// Shows a small 16pt icon and the filename, truncated with ellipsis.
/// Minimal chrome — no metadata, no hover overlays.
final class BriefColumnItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("BriefColumnItem")

    /// The file item this cell represents.
    var fileItem: FileItem?

    /// 16pt file/folder icon.
    private let iconView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    /// Filename label, truncated with ellipsis for long names.
    private let nameLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    /// Background view for selection highlight.
    private let selectionBox: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    /// Pre-built folder SF Symbol (shared across all brief items).
    private static let folderImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: "Folder"
        )?.withSymbolConfiguration(config)
    }()

    /// Icon cache keyed by file extension to avoid repeated NSWorkspace lookups.
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        container.addSubview(selectionBox)
        container.addSubview(iconView)
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            // Selection box fills the cell
            selectionBox.topAnchor.constraint(equalTo: container.topAnchor),
            selectionBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            selectionBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // 16pt icon with left padding
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            // Filename label to the right of the icon
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }

    override var isSelected: Bool {
        didSet {
            selectionBox.isHidden = !isSelected
        }
    }

    // MARK: - Configuration

    /// Configures the cell with a file item. Sets icon, name, colors, and opacity.
    func configure(with item: FileItem) {
        fileItem = item

        let theme = ThemeManager.shared.activeTheme
        let hiddenAlpha: CGFloat = item.isHidden ? 0.75 : 1.0

        // Filename
        nameLabel.stringValue = item.name
        nameLabel.font = FontManager.shared.activeFont.withSize(12)
        nameLabel.textColor = item.isDirectory
            ? theme.chromeAccent.withAlphaComponent(0.7 * hiddenAlpha)
            : theme.explorerText.withAlphaComponent(hiddenAlpha)

        // Icon
        iconView.alphaValue = hiddenAlpha
        if item.isDirectory {
            iconView.image = Self.folderImage
            iconView.contentTintColor = theme.chromeAccent.withAlphaComponent(0.7)
        } else {
            iconView.image = Self.cachedIcon(for: item)
            iconView.contentTintColor = nil
        }

        // Selection highlight color
        selectionBox.layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.15).cgColor
    }

    /// Returns a cached file icon for the item, keyed by file extension.
    private static func cachedIcon(for item: FileItem) -> NSImage {
        let ext = item.url.pathExtension.lowercased() as NSString
        if let cached = iconCache.object(forKey: ext) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        iconCache.setObject(icon, forKey: ext)
        return icon
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        iconView.contentTintColor = nil
        iconView.alphaValue = 1.0
        nameLabel.stringValue = ""
        selectionBox.isHidden = true
        fileItem = nil
    }
}
