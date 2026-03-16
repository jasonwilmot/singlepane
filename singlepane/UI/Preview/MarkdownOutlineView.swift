// MarkdownOutlineView.swift
// Displays a navigable outline of markdown headings with themed styling.
// Shows H1–H6 entries with per-level colors, indentation, and font sizes
// matching the editor's heading hierarchy. Supports scroll spy: highlights
// the currently visible heading as the user scrolls the editor/preview.

import AppKit

@MainActor
final class MarkdownOutlineView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var headings: [MarkdownHeading] = []

    /// Index of the heading currently visible in the editor/preview (scroll spy).
    private var activeHeadingIndex: Int = -1

    /// Called when the user clicks a heading in the outline.
    /// Parameters: the heading struct and its index in the headings array.
    var onHeadingSelected: ((MarkdownHeading, Int) -> Void)?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        startObservingTheme()
        startObservingFont()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true

        // Single column for heading titles
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Use non-required priority so constraints yield gracefully when
        // the NSSplitView collapses this view to zero height.
        let top = scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        let bottom = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        top.priority = .init(999)
        bottom.priority = .init(999)

        NSLayoutConstraint.activate([
            top,
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom,
        ])

        applyTheme()
    }

    // MARK: - Data

    /// Updates the outline with new headings parsed from markdown text.
    func updateHeadings(_ newHeadings: [MarkdownHeading]) {
        headings = newHeadings
        tableView.reloadData()
    }

    /// Highlights the heading at the given index as the currently visible one (scroll spy).
    func setActiveHeading(at index: Int) {
        guard index != activeHeadingIndex else { return }
        let oldIndex = activeHeadingIndex
        activeHeadingIndex = index

        // Reload only the changed rows for efficiency
        var rows = IndexSet()
        if oldIndex >= 0, oldIndex < headings.count { rows.insert(oldIndex) }
        if index >= 0, index < headings.count { rows.insert(index) }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))

        // Scroll the active heading into view in the outline
        if index >= 0, index < headings.count {
            tableView.scrollRowToVisible(index)
        }
    }

    /// The current headings array, for external queries.
    var currentHeadings: [MarkdownHeading] { headings }

    // MARK: - Actions

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < headings.count else { return }
        onHeadingSelected?(headings[row], row)
    }

    // MARK: - Theme

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = theme.backgroundColor.cgColor
        tableView.backgroundColor = theme.backgroundColor
        tableView.reloadData()
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

    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.tableView.reloadData()
                self?.startObservingFont()
            }
        }
    }
}

// MARK: - NSTableViewDataSource

extension MarkdownOutlineView: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        headings.count
    }
}

// MARK: - NSTableViewDelegate

extension MarkdownOutlineView: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < headings.count else { return nil }
        let heading = headings[row]
        let theme = ThemeManager.shared.activeTheme
        let baseFont = FontManager.shared.activeFont

        // Container view with indentation per heading level
        let cellID = NSUserInterfaceItemIdentifier("outlineHeading")
        let container: NSView
        let label: NSTextField

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) {
            container = existing
            label = existing.subviews.compactMap { $0 as? NSTextField }.first ?? NSTextField(labelWithString: "")
        } else {
            container = NSView()
            container.identifier = cellID
            let newLabel = NSTextField(labelWithString: "")
            newLabel.isEditable = false
            newLabel.isBordered = false
            newLabel.drawsBackground = false
            newLabel.lineBreakMode = .byTruncatingTail
            newLabel.cell?.truncatesLastVisibleLine = true
            newLabel.translatesAutoresizingMaskIntoConstraints = false
            newLabel.tag = 100
            container.addSubview(newLabel)

            // Vertical centering — leading is set dynamically per row
            NSLayoutConstraint.activate([
                newLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                newLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
            ])
            label = newLabel
        }

        // Remove old leading constraint and set new one based on heading level
        for constraint in container.constraints where constraint.firstAttribute == .leading
            && constraint.firstItem === label {
            constraint.isActive = false
        }
        let indent = CGFloat(heading.level - 1) * 12
        label.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: 8 + indent
        ).isActive = true

        // Style: per-level color, scaled font, bold for active heading
        let level = heading.level - 1  // 0-based
        let paletteIndex = MarkdownHeadingParser.paletteIndices[min(level, 5)]
        let scale = MarkdownHeadingParser.fontScales[min(level, 5)]
        let isActive = (row == activeHeadingIndex)

        // Smaller font for outline; scale preserves relative heading hierarchy
        let fontSize = baseFont.pointSize * scale * 0.75
        let font: NSFont
        if isActive {
            font = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold),
                          size: fontSize) ?? NSFont(descriptor: baseFont.fontDescriptor, size: fontSize)!
        } else {
            font = NSFont(descriptor: baseFont.fontDescriptor, size: fontSize)
                ?? NSFont.systemFont(ofSize: fontSize)
        }

        label.stringValue = heading.title
        label.font = font
        label.textColor = theme.paletteColor(at: paletteIndex)

        return container
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()

        // Subtle background highlight for the active heading (scroll spy)
        if row == activeHeadingIndex {
            rowView.wantsLayer = true
            let theme = ThemeManager.shared.activeTheme
            rowView.layer?.backgroundColor = theme.foregroundColor.withAlphaComponent(0.08).cgColor
            rowView.layer?.cornerRadius = 4
        }

        return rowView
    }
}
