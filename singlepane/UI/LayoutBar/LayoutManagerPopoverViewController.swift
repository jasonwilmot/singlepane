// LayoutManagerPopoverViewController.swift
// Content view controller for the Layout Manager popover.
// Presents three sections: panel order row, layout grid (presets + custom),
// and a "+" button to save a new custom layout.
// Manages its own delegate for layout selection, reorder, save, and delete.

import AppKit

// MARK: - Delegate Protocol

/// Callbacks from the Layout Manager popover to the parent (LayoutBarView / WorkspaceVC).
@MainActor
protocol LayoutManagerPopoverDelegate: AnyObject {
    func layoutManagerDidSelectLayout(_ layout: SnapLayout)
    func layoutManagerDidSelectCustomLayout(_ layout: CustomLayout)
    func layoutManagerDidReorderColumns(_ newOrder: [PanelType])
    func layoutManagerDidRequestSaveCustomLayout()
    func layoutManagerDidRequestDeleteCustomLayout(at index: Int)
}

// MARK: - LayoutManagerPopoverViewController

@MainActor
final class LayoutManagerPopoverViewController: NSViewController {

    // MARK: - Properties

    weak var popoverDelegate: LayoutManagerPopoverDelegate?

    /// The currently active layout, used to highlight the active row.
    var activeLayoutState: ActiveLayoutState = .preset(.allEqual)

    /// Current global column order.
    var columnOrder: [PanelType]

    /// Reference to the owning popover for programmatic dismissal.
    weak var owningPopover: NSPopover?

    // MARK: - UI Elements

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private var panelOrderRow: PanelOrderRowView!
    private var layoutRows: [LayoutRowView] = []
    private var customLayoutRows: [LayoutRowView] = []
    private var customDivider: NSView?
    private var addButton: NSButton?

    // MARK: - Constants

    private static let popoverWidth: CGFloat = 260
    private static let padding: CGFloat = 12
    private static let sectionSpacing: CGFloat = 10
    private static let rowSpacing: CGFloat = 4

    // MARK: - Init

    init(columnOrder: [PanelType]) {
        self.columnOrder = columnOrder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: 400 // Initial; will be adjusted
        ))
        container.wantsLayer = true
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Build UI

    private func buildUI() {
        let theme = ThemeManager.shared.activeTheme

        // Main vertical stack for all content
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Self.sectionSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // -- Section 1: Panel Order --
        let orderHeader = makeSectionHeader("Panel Order")
        contentStack.addArrangedSubview(orderHeader)

        panelOrderRow = PanelOrderRowView(columnOrder: columnOrder)
        panelOrderRow.onReorder = { [weak self] newOrder in
            self?.handleColumnReorder(newOrder)
        }
        contentStack.addArrangedSubview(panelOrderRow)

        // -- Divider --
        contentStack.addArrangedSubview(makeSectionDivider())

        // -- Section 2: Layout Presets --
        let layoutHeader = makeSectionHeader("Layouts")
        contentStack.addArrangedSubview(layoutHeader)

        buildPresetRows()

        // -- Custom Layouts --
        buildCustomLayoutSection()

        // -- Divider --
        contentStack.addArrangedSubview(makeSectionDivider())

        // -- Section 3: Add Button --
        let addBtn = makeAddButton()
        contentStack.addArrangedSubview(addBtn)
        addButton = addBtn

        // Wrap in scroll view for overflow
        scrollView.documentView = contentStack
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.padding),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.padding),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.padding),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.padding),

            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        updatePreferredContentSize()
    }

    // MARK: - Preset Rows

    private func buildPresetRows() {
        for layout in SnapLayout.allCases {
            let row = LayoutRowView(
                layoutID: layout.rawValue,
                columnOrder: columnOrder,
                visiblePanels: layout.visiblePanels,
                displayName: layout.displayName,
                isActive: activeLayoutState == .preset(layout)
            )
            row.onSelect = { [weak self] in
                self?.popoverDelegate?.layoutManagerDidSelectLayout(layout)
                self?.owningPopover?.close()
            }
            row.onHotkeyChanged = { [weak self] in
                self?.refreshAllRows()
            }
            contentStack.addArrangedSubview(row)
            layoutRows.append(row)
        }
    }

    // MARK: - Custom Layout Section

    private func buildCustomLayoutSection() {
        let customs = CustomLayoutManager.shared.customLayouts
        guard !customs.isEmpty else { return }

        // Divider between presets and custom
        let divider = makeSectionDivider()
        contentStack.addArrangedSubview(divider)
        customDivider = divider

        let header = makeSectionHeader("Custom Layouts")
        contentStack.addArrangedSubview(header)

        for (index, layout) in customs.enumerated() {
            let isActive: Bool
            if case .custom(let active) = activeLayoutState {
                isActive = active.id == layout.id
            } else {
                isActive = false
            }

            let row = LayoutRowView(
                layoutID: layout.id.uuidString,
                columnOrder: layout.columnOrder,
                visiblePanels: Set(layout.panelVisibility.filter(\.value).map(\.key)),
                displayName: "Custom \(index + 1)",
                isActive: isActive,
                customVisibility: layout.panelVisibility,
                badgeNumber: index + 1,
                isDeletable: true
            )
            row.onSelect = { [weak self] in
                self?.popoverDelegate?.layoutManagerDidSelectCustomLayout(layout)
                self?.owningPopover?.close()
            }
            row.onDelete = { [weak self] in
                self?.popoverDelegate?.layoutManagerDidRequestDeleteCustomLayout(at: index)
                self?.reloadCustomLayouts()
            }
            row.onHotkeyChanged = { [weak self] in
                self?.refreshAllRows()
            }
            contentStack.addArrangedSubview(row)
            customLayoutRows.append(row)
        }
    }

    /// Rebuilds just the custom layout rows after save or delete.
    func reloadCustomLayouts() {
        // Remove existing custom rows and their header/divider
        for row in customLayoutRows {
            contentStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        customLayoutRows.removeAll()

        if let divider = customDivider {
            contentStack.removeArrangedSubview(divider)
            divider.removeFromSuperview()
            customDivider = nil
        }

        // Remove the section header if it exists (it's the view right after the divider)
        // Find and remove any "Custom Layouts" header
        for subview in contentStack.arrangedSubviews {
            if let label = subview as? NSTextField, label.stringValue == "Custom Layouts" {
                contentStack.removeArrangedSubview(label)
                label.removeFromSuperview()
                break
            }
        }

        // Re-insert custom section before the last divider + add button
        buildCustomLayoutSection()

        // Update add button state
        addButton?.isEnabled = CustomLayoutManager.shared.canSave
        addButton?.alphaValue = CustomLayoutManager.shared.canSave ? 1.0 : 0.4

        updatePreferredContentSize()
    }

    // MARK: - Column Reorder

    private func handleColumnReorder(_ newOrder: [PanelType]) {
        columnOrder = newOrder
        popoverDelegate?.layoutManagerDidReorderColumns(newOrder)

        // Update all preset row icons to reflect the new column order
        for (index, layout) in SnapLayout.allCases.enumerated() {
            guard index < layoutRows.count else { break }
            layoutRows[index].updateColumnOrder(newOrder, visiblePanels: layout.visiblePanels)
        }
    }

    // MARK: - Refresh

    /// Redraws all rows (e.g., after a hotkey change to update pill states).
    private func refreshAllRows() {
        for row in layoutRows { row.refreshHotkey() }
        for row in customLayoutRows { row.refreshHotkey() }
    }

    // MARK: - UI Helpers

    /// Creates a dim section header label.
    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = FontManager.shared.activeFont.withSize(9)
        label.textColor = ThemeManager.shared.activeTheme.chromeTextSecondary
        return label
    }

    /// Creates a 1px horizontal divider.
    private func makeSectionDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = ThemeManager.shared.activeTheme.chromeBorder.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.widthAnchor.constraint(equalToConstant: Self.popoverWidth - Self.padding * 2),
        ])
        return divider
    }

    /// Creates the "+" save custom layout button with an accent background.
    private func makeAddButton() -> NSButton {
        let theme = ThemeManager.shared.activeTheme
        let button = PointerButton(title: "+ Save Current Layout", target: self, action: #selector(addButtonClicked))
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = FontManager.shared.activeFont.withSize(11)
        button.contentTintColor = theme.chromeText
        button.wantsLayer = true
        button.layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.25).cgColor
        button.layer?.cornerRadius = 4
        button.isEnabled = CustomLayoutManager.shared.canSave
        button.alphaValue = CustomLayoutManager.shared.canSave ? 1.0 : 0.4

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.popoverWidth - Self.padding * 2),
            button.heightAnchor.constraint(equalToConstant: 26),
        ])
        return button
    }

    @objc private func addButtonClicked() {
        popoverDelegate?.layoutManagerDidRequestSaveCustomLayout()
        reloadCustomLayouts()
    }

    // MARK: - Sizing

    /// Computes the preferred content size based on actual content height.
    private func updatePreferredContentSize() {
        contentStack.layoutSubtreeIfNeeded()
        let contentHeight = contentStack.fittingSize.height + Self.padding * 2
        let maxHeight: CGFloat = 500
        let height = min(contentHeight, maxHeight)
        preferredContentSize = NSSize(width: Self.popoverWidth, height: height)
    }
}

// MARK: - PointerButton

/// NSButton subclass that shows a pointing-hand cursor on hover.
private final class PointerButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
