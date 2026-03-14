// PanelOrderRowView.swift
// Horizontal row of 3 draggable panel boxes for reordering columns.
// Each box shows an SF Symbol icon + short label ("Terminal", "Files", "Editor").
// Drag-and-drop reorders the boxes and fires a callback with the new column order.
// Lives at the top of the Layout Manager popover.

import AppKit

@MainActor
final class PanelOrderRowView: NSView {

    // MARK: - Properties

    /// Current column order (mutable — updated on drag reorder).
    private(set) var columnOrder: [PanelType]

    /// Called when the user finishes a drag-and-drop reorder.
    var onReorder: (([PanelType]) -> Void)?

    /// Individual panel box views, ordered left-to-right.
    private var boxViews: [PanelBoxView] = []

    /// Stack view containing the boxes.
    private let stackView = NSStackView()

    // MARK: - Constants

    private static let boxWidth: CGFloat = 64
    private static let boxHeight: CGFloat = 48
    private static let spacing: CGFloat = 8

    // MARK: - Init

    init(columnOrder: [PanelType]) {
        self.columnOrder = columnOrder
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = Self.spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        rebuildBoxes()
    }

    /// Rebuilds the box views from the current column order.
    private func rebuildBoxes() {
        for box in boxViews {
            stackView.removeArrangedSubview(box)
            box.removeFromSuperview()
        }
        boxViews.removeAll()

        for panelType in columnOrder {
            let box = PanelBoxView(panelType: panelType)
            box.onDragBegan = { [weak self] draggedType in
                self?.handleDragBegan(draggedType)
            }
            box.onDragEntered = { [weak self] targetType in
                self?.handleDragEntered(targetType)
            }
            box.onDragCompleted = { [weak self] in
                self?.handleDragCompleted()
            }
            stackView.addArrangedSubview(box)
            boxViews.append(box)
        }
    }

    /// Updates the column order and rebuilds boxes.
    func updateColumnOrder(_ newOrder: [PanelType]) {
        columnOrder = newOrder
        rebuildBoxes()
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        let width = Self.boxWidth * 3 + Self.spacing * 2
        return NSSize(width: width, height: Self.boxHeight)
    }

    // MARK: - Drag Handling

    /// The panel type currently being dragged.
    private var draggedPanel: PanelType?

    private func handleDragBegan(_ panelType: PanelType) {
        draggedPanel = panelType
    }

    /// Swaps the dragged panel with the target panel on hover.
    private func handleDragEntered(_ targetType: PanelType) {
        guard let dragged = draggedPanel, dragged != targetType else { return }
        guard let fromIndex = columnOrder.firstIndex(of: dragged),
              let toIndex = columnOrder.firstIndex(of: targetType) else { return }

        columnOrder.swapAt(fromIndex, toIndex)
        rebuildBoxes()
    }

    /// Fires the reorder callback when the drag session ends.
    private func handleDragCompleted() {
        draggedPanel = nil
        onReorder?(columnOrder)
    }
}

// MARK: - PanelBoxView

/// A single draggable box representing a panel column.
/// Shows an SF Symbol icon above a short text label, inside a bordered container.
@MainActor
private final class PanelBoxView: NSView, NSDraggingSource {

    // MARK: - Properties

    let panelType: PanelType

    /// Callbacks for drag coordination with the parent row.
    var onDragBegan: ((PanelType) -> Void)?
    var onDragEntered: ((PanelType) -> Void)?
    var onDragCompleted: (() -> Void)?

    // MARK: - Constants

    private static let boxWidth: CGFloat = 64
    private static let boxHeight: CGFloat = 48
    private static let cornerRadius: CGFloat = 6

    /// Custom pasteboard type for panel reordering.
    static let pasteboardType = NSPasteboard.PasteboardType("com.velocity.panelType")

    // MARK: - Init

    init(panelType: PanelType) {
        self.panelType = panelType
        super.init(frame: NSRect(x: 0, y: 0, width: Self.boxWidth, height: Self.boxHeight))
        wantsLayer = true

        setupAppearance()
        setupContent()

        // Register as a drag destination
        registerForDraggedTypes([Self.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.boxWidth, height: Self.boxHeight)
    }

    // MARK: - Setup

    private func setupAppearance() {
        let theme = ThemeManager.shared.activeTheme
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = theme.chromeBorder.cgColor
        layer?.backgroundColor = theme.chromeTextSecondary.withAlphaComponent(0.06).cgColor
    }

    private func setupContent() {
        let theme = ThemeManager.shared.activeTheme

        // SF Symbol icon
        let imageView = NSImageView()
        imageView.image = NSImage(
            systemSymbolName: panelType.symbolName,
            accessibilityDescription: panelType.shortLabel
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        imageView.contentTintColor = theme.chromeText
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Short label
        let label = NSTextField(labelWithString: panelType.shortLabel)
        label.font = FontManager.shared.activeFont.withSize(9)
        label.textColor = theme.chromeTextSecondary
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
        ])
    }

    // MARK: - Mouse Handling (Drag Source)

    override func mouseDown(with event: NSEvent) {
        // Intentionally empty — wait for mouseDragged to start the drag session.
    }

    override func mouseDragged(with event: NSEvent) {
        onDragBegan?(panelType)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(panelType.rawValue, forType: Self.pasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: snapshot())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragCompleted?()
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEntered?(panelType)
        return .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    // MARK: - Snapshot

    /// Creates a bitmap image of this view for the drag preview.
    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - PanelType Extensions

extension PanelType {

    /// SF Symbol name for the panel order box icon.
    var symbolName: String {
        switch self {
        case .terminal: return "terminal"
        case .explorer: return "folder"
        case .preview:  return "doc.text"
        }
    }

    /// Short label for the panel order box.
    var shortLabel: String {
        switch self {
        case .terminal: return "Terminal"
        case .explorer: return "Files"
        case .preview:  return "Editor"
        }
    }
}
