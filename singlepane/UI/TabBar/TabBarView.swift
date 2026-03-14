// TabBarView.swift
// Custom NSStackView-based tab bar supporting horizontal and vertical orientation.
// Includes "+" button for creating new tabs and a group button to show all tabs
// simultaneously in a split/grid arrangement.

import AppKit

// MARK: - Top-Aligned Clip View

/// Flipped clip view that pins content to the top edge.
/// Standard NSClipView uses bottom-origin coordinates, causing content shorter
/// than the visible area to sit at the bottom. Flipping ensures tabs start
/// from the top in vertical orientation.
@MainActor
final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - Event-Forwarding Scroll View

/// Scroll view that always forwards mouse events to the document view's subviews.
/// Standard NSScrollView intercepts clicks during/after momentum scrolling to stop
/// the scroll, preventing the click from reaching the intended target (e.g. tab items).
/// This subclass ensures clicks always reach the document view's children by re-routing
/// hits that land on the scroll view infrastructure (clip view, scroller) to the
/// document view hierarchy instead.
@MainActor
final class EventForwardingScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }

        let standardHit = super.hitTest(point)

        // If the standard hit test returned the scroll view itself, the clip view,
        // or a scroller, the scroll view is intercepting the event (e.g. to stop
        // momentum scrolling). Re-route to the document view so subviews get the click.
        if standardHit === self || standardHit === contentView || standardHit is NSScroller {
            let local = convert(point, from: superview)
            let clipLocal = contentView.convert(local, from: self)
            if let target = documentView?.hitTest(clipLocal), target !== documentView {
                return target
            }
        }

        return standardHit
    }
}

// MARK: - Delegate Protocol

/// Tab bar events forwarded to the owning container.
@MainActor
protocol TabBarDelegate: AnyObject {
    func tabBarDidSelectTab(at index: Int)
    func tabBarDidCloseTab(at index: Int)
    func tabBarDidRequestNewTab()

    /// Called when the user toggles "group all" on — all tabs shown simultaneously.
    func tabBarDidGroupAllTabs(_ indices: Set<Int>)

    /// Called when the user toggles "group all" off — single tab displayed.
    func tabBarDidUngroupTabs(focusedIndex: Int)

    /// Called when the user clicks a tab while grouped — changes focus within the split.
    func tabBarDidFocusTab(at index: Int)

    /// Called when the user cycles the split arrangement mode.
    func tabBarDidChangeArrangement(_ mode: ArrangementMode)

    /// Called when the user toggles tab bar orientation (horizontal ↔ vertical).
    func tabBarDidToggleOrientation()

    /// Called when the user double-clicks a tab.
    func tabBarDidDoubleClickTab(at index: Int)
}

// Default no-op implementations so only terminal containers need grouping.
extension TabBarDelegate {
    func tabBarDidGroupAllTabs(_ indices: Set<Int>) {}
    func tabBarDidUngroupTabs(focusedIndex: Int) {}
    func tabBarDidFocusTab(at index: Int) {}
    func tabBarDidChangeArrangement(_ mode: ArrangementMode) {}
    func tabBarDidToggleOrientation() {}
    func tabBarDidDoubleClickTab(at index: Int) {}
}

// MARK: - Tab Bar View

@MainActor
final class TabBarView: NSView {

    // MARK: - Properties

    weak var delegate: TabBarDelegate?

    /// Whether to show the "+" button for creating new tabs. Defaults to true.
    /// Updating this property after init hides/shows the button and re-applies layout.
    var showAddButton: Bool = true {
        didSet {
            addButton.isHidden = !showAddButton
            updateOrientation()
        }
    }

    /// Style passed to each TabItemView. Defaults to `.full`.
    var tabItemStyle: TabItemView.Style = .full

    /// Whether the group-all button should be available. Defaults to false.
    /// Set to true for terminal tab bars where grouping is supported.
    var supportsGrouping: Bool = false

    /// Whether closing the last remaining tab is allowed. Defaults to false.
    /// When true, the close button fires the delegate even for the final tab.
    /// Used by the preview file tab bar where zero tabs = empty placeholder.
    var allowCloseLastTab: Bool = false

    /// When true, the delegate is responsible for calling `removeTab(at:)` to
    /// complete the close. Used when the close may require async confirmation
    /// (e.g. unsaved changes prompt). Defaults to false.
    var delegateHandlesClose: Bool = false

    /// When true, the tab bar draws no background — the parent view provides
    /// the chrome color. Used when the tab bar shares a row with other controls
    /// and a single unified background is desired. Defaults to false.
    var drawsOwnBackground: Bool = true

    /// Extra trailing space reserved for external controls overlaid on the tab row.
    /// The scroll view stops this many points before the trailing edge.
    var trailingReservedWidth: CGFloat = 0

    /// Whether the orientation toggle button should be visible. Defaults to false.
    /// Set to true for terminal tab bars where horizontal/vertical switching is supported.
    var supportsOrientationToggle: Bool = false {
        didSet {
            orientationButton.isHidden = !supportsOrientationToggle
            // Rebuild layout so the button chain includes/excludes this button
            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints.removeAll()
            switch orientation {
            case .horizontal: applyHorizontalLayout()
            case .vertical:   applyVerticalLayout()
            }
        }
    }

    /// Hides tab items and add button while keeping the bar's chrome background visible.
    /// Used for editor-only files where the bar serves as a toolbar strip for buttons.
    var showTabContent: Bool = true {
        didSet {
            tabScrollView.isHidden = !showTabContent
            addButton.isHidden = !showTabContent || !showAddButton
        }
    }

    private let tabScrollView = EventForwardingScrollView()
    private let stackView = NSStackView()
    private let addButton = NSButton()
    private let groupButton = NSButton()
    private let arrangementButton = NSButton()
    private let orientationButton = NSButton()

    /// Stored layout constraints — deactivated on orientation change.
    private var layoutConstraints: [NSLayoutConstraint] = []

    private var tabItems: [TabItemView] = []
    private(set) var selectedIndex: Int = 0

    /// Indices of all selected tabs when grouped.
    /// Contains a single index when not grouped.
    private(set) var selectedIndices: Set<Int> = [0]

    /// Whether all tabs are currently shown simultaneously in a split/grid.
    private(set) var isGrouped: Bool = false

    /// How multiple terminal panes are arranged. Persisted across sessions.
    private(set) var arrangementMode: ArrangementMode = {
        if let raw = UserDefaults.standard.string(forKey: ArrangementMode.defaultsKey),
           let mode = ArrangementMode(rawValue: raw) {
            return mode
        }
        return .vertical
    }()

    var orientation: TabOrientation = .horizontal {
        didSet { updateOrientation() }
    }

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true

        // Stack view holds tab items
        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Scroll view wraps the stack so tabs scroll instead of forcing window width.
        // No visible scrollbar — scroll via trackpad/mouse wheel only (matches breadcrumbs).
        tabScrollView.documentView = stackView
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.drawsBackground = false
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.verticalScrollElasticity = .none
        tabScrollView.automaticallyAdjustsContentInsets = false
        tabScrollView.contentInsets = NSEdgeInsetsZero
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabScrollView)

        // "+" button to add new tabs (hidden when showAddButton is false)
        addButton.bezelStyle = .accessoryBarAction
        addButton.title = "+"
        addButton.font = FontManager.shared.activeFont.withSize(14)
        addButton.target = self
        addButton.action = #selector(addButtonClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        addButton.setContentHuggingPriority(.required, for: .vertical)
        addButton.isHidden = !showAddButton
        addSubview(addButton)

        // Group toggle — shows all tabs simultaneously. Hidden until 2+ tabs exist.
        groupButton.bezelStyle = .accessoryBarAction
        groupButton.image = NSImage(
            systemSymbolName: "square.stack.3d.up",
            accessibilityDescription: "Group all tabs"
        )
        groupButton.imagePosition = .imageOnly
        groupButton.target = self
        groupButton.action = #selector(groupButtonClicked)
        groupButton.translatesAutoresizingMaskIntoConstraints = false
        groupButton.setContentHuggingPriority(.required, for: .horizontal)
        groupButton.setContentHuggingPriority(.required, for: .vertical)
        groupButton.isHidden = true
        addSubview(groupButton)

        // Arrangement cycle — cycles vertical/horizontal/grid. Hidden until grouped.
        arrangementButton.bezelStyle = .accessoryBarAction
        arrangementButton.image = NSImage(
            systemSymbolName: arrangementMode.symbolName,
            accessibilityDescription: "Cycle split arrangement"
        )
        arrangementButton.imagePosition = .imageOnly
        arrangementButton.target = self
        arrangementButton.action = #selector(arrangementButtonClicked)
        arrangementButton.translatesAutoresizingMaskIntoConstraints = false
        arrangementButton.setContentHuggingPriority(.required, for: .horizontal)
        arrangementButton.setContentHuggingPriority(.required, for: .vertical)
        arrangementButton.isHidden = true
        addSubview(arrangementButton)

        // Orientation toggle — switches tab bar between horizontal (top) and vertical (sidebar).
        orientationButton.bezelStyle = .accessoryBarAction
        orientationButton.image = NSImage(
            systemSymbolName: orientationSymbolName,
            accessibilityDescription: "Toggle tab orientation"
        )
        orientationButton.imagePosition = .imageOnly
        orientationButton.target = self
        orientationButton.action = #selector(orientationButtonClicked)
        orientationButton.translatesAutoresizingMaskIntoConstraints = false
        orientationButton.setContentHuggingPriority(.required, for: .horizontal)
        orientationButton.setContentHuggingPriority(.required, for: .vertical)
        orientationButton.isHidden = !supportsOrientationToggle
        addSubview(orientationButton)

        applyHorizontalLayout()
    }

    // MARK: - Drawing

    /// Draws a 1px horizontal rule at the bottom of the tab bar to ground the tabs.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = ThemeManager.shared.activeTheme
        theme.chromeBorder.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    // MARK: - Orientation

    private func updateOrientation() {
        stackView.orientation = orientation == .horizontal ? .horizontal : .vertical
        stackView.spacing = orientation == .horizontal ? 4 : 0

        // Update tab item styling for the new orientation
        let itemMode: TabItemView.OrientationMode = orientation == .horizontal ? .horizontal : .vertical
        for item in tabItems {
            item.setOrientationMode(itemMode)
        }

        // Tear down stored layout constraints and re-apply for new orientation
        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints.removeAll()

        switch orientation {
        case .horizontal:
            // Restore default clip view for horizontal scroll
            let clipView = NSClipView()
            clipView.drawsBackground = false
            tabScrollView.contentView = clipView
            tabScrollView.documentView = stackView
            tabScrollView.hasHorizontalScroller = false
            tabScrollView.hasVerticalScroller = false
            tabScrollView.horizontalScrollElasticity = .allowed
            tabScrollView.verticalScrollElasticity = .none
            applyHorizontalLayout()
        case .vertical:
            // Use flipped clip view so tabs align to top, not bottom
            let clipView = TopAlignedClipView()
            clipView.drawsBackground = false
            tabScrollView.contentView = clipView
            tabScrollView.documentView = stackView
            tabScrollView.hasHorizontalScroller = false
            tabScrollView.hasVerticalScroller = false
            tabScrollView.horizontalScrollElasticity = .none
            tabScrollView.verticalScrollElasticity = .allowed
            applyVerticalLayout()
        }
    }

    private func applyHorizontalLayout() {
        // Stack fills scroll view height, grows horizontally to scroll
        var constraints = [
            stackView.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            stackView.heightAnchor.constraint(equalTo: tabScrollView.contentView.heightAnchor),

            tabScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            tabScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        if !showAddButton {
            constraints.append(
                tabScrollView.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -trailingReservedWidth
                )
            )
        } else {
            // Buttons are anchored from the trailing edge inward.
            // The rightmost visible button sits flush at trailing-4.
            // Chain: trailing ← arrangement ← group ← add ← scrollView
            // Hidden buttons collapse (zero size) so the next visible button fills the slot.
            let buttonSize: CGFloat = 24
            let gap: CGFloat = 2

            constraints += [
                addButton.centerYAnchor.constraint(equalTo: tabScrollView.centerYAnchor),
                addButton.widthAnchor.constraint(equalToConstant: buttonSize),
                addButton.heightAnchor.constraint(equalToConstant: buttonSize),

                groupButton.centerYAnchor.constraint(equalTo: tabScrollView.centerYAnchor),
                groupButton.widthAnchor.constraint(equalToConstant: buttonSize),
                groupButton.heightAnchor.constraint(equalToConstant: buttonSize),

                arrangementButton.centerYAnchor.constraint(equalTo: tabScrollView.centerYAnchor),
                arrangementButton.widthAnchor.constraint(equalToConstant: buttonSize),
                arrangementButton.heightAnchor.constraint(equalToConstant: buttonSize),

                orientationButton.centerYAnchor.constraint(equalTo: tabScrollView.centerYAnchor),
                orientationButton.widthAnchor.constraint(equalToConstant: buttonSize),
                orientationButton.heightAnchor.constraint(equalToConstant: buttonSize),
            ]

            // Build the trailing chain based on which buttons are visible.
            // Rightmost visible button pins to trailing edge; others chain left.
            // Chain order: trailing ← orientation ← arrangement ← group ← add ← scrollView
            var anchor = trailingAnchor
            let inset: CGFloat = -4

            if !orientationButton.isHidden {
                constraints.append(orientationButton.trailingAnchor.constraint(equalTo: anchor, constant: inset))
                anchor = orientationButton.leadingAnchor
            }
            if !arrangementButton.isHidden {
                let offset: CGFloat = anchor == trailingAnchor ? inset : -gap
                constraints.append(arrangementButton.trailingAnchor.constraint(equalTo: anchor, constant: offset))
                anchor = arrangementButton.leadingAnchor
            }
            if !groupButton.isHidden {
                let offset: CGFloat = anchor == trailingAnchor ? inset : -gap
                constraints.append(groupButton.trailingAnchor.constraint(equalTo: anchor, constant: offset))
                anchor = groupButton.leadingAnchor
            }
            // Add button is always visible when showAddButton is true
            let addOffset: CGFloat = anchor == trailingAnchor ? inset : -gap
            constraints.append(addButton.trailingAnchor.constraint(equalTo: anchor, constant: addOffset))
            constraints.append(tabScrollView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -gap))
        }

        layoutConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    private func applyVerticalLayout() {
        // Stack fills scroll view width, grows vertically to scroll
        var constraints = [
            stackView.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            stackView.widthAnchor.constraint(equalTo: tabScrollView.contentView.widthAnchor),

            tabScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        if !showAddButton {
            constraints.append(
                tabScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 2)
            )
        } else {
            let buttonSize: CGFloat = 24
            let gap: CGFloat = 2

            // Buttons in a horizontal row above the tabs, right-aligned
            constraints += [
                addButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                addButton.widthAnchor.constraint(equalToConstant: buttonSize),
                addButton.heightAnchor.constraint(equalToConstant: buttonSize),

                groupButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                groupButton.widthAnchor.constraint(equalToConstant: buttonSize),
                groupButton.heightAnchor.constraint(equalToConstant: buttonSize),

                arrangementButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                arrangementButton.widthAnchor.constraint(equalToConstant: buttonSize),
                arrangementButton.heightAnchor.constraint(equalToConstant: buttonSize),

                orientationButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                orientationButton.widthAnchor.constraint(equalToConstant: buttonSize),
                orientationButton.heightAnchor.constraint(equalToConstant: buttonSize),

                tabScrollView.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: gap),
            ]

            // Build horizontal trailing chain: rightmost visible button pins to trailing edge
            // Chain order: trailing ← orientation ← arrangement ← group ← add
            var anchor = trailingAnchor
            let inset: CGFloat = -4

            if !orientationButton.isHidden {
                constraints.append(orientationButton.trailingAnchor.constraint(equalTo: anchor, constant: inset))
                anchor = orientationButton.leadingAnchor
            }
            if !arrangementButton.isHidden {
                let offset: CGFloat = anchor == trailingAnchor ? inset : -gap
                constraints.append(arrangementButton.trailingAnchor.constraint(equalTo: anchor, constant: offset))
                anchor = arrangementButton.leadingAnchor
            }
            if !groupButton.isHidden {
                let offset: CGFloat = anchor == trailingAnchor ? inset : -gap
                constraints.append(groupButton.trailingAnchor.constraint(equalTo: anchor, constant: offset))
                anchor = groupButton.leadingAnchor
            }
            let addOffset: CGFloat = anchor == trailingAnchor ? inset : -gap
            constraints.append(addButton.trailingAnchor.constraint(equalTo: anchor, constant: addOffset))
        }

        layoutConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Tab Management

    /// Add a tab with the given title. Selects it automatically.
    func addTab(title: String) {
        let index = tabItems.count
        let tabItem = TabItemView(title: title, index: index, style: tabItemStyle)
        tabItem.onSelect = { [weak self] idx, _ in
            self?.handleTabClick(at: idx)
        }
        tabItem.onClose = { [weak self] idx in self?.closeTab(at: idx) }
        tabItem.onDoubleClick = { [weak self] idx in
            self?.delegate?.tabBarDidDoubleClickTab(at: idx)
        }

        // Match current orientation mode for vertical row styling
        if orientation == .vertical {
            tabItem.setOrientationMode(.vertical)
        }

        tabItems.append(tabItem)
        stackView.addArrangedSubview(tabItem)

        // If grouped, add the new tab to the visible set and rebuild
        if isGrouped {
            selectedIndices = Set(0..<tabItems.count)
            updateSelectionAppearance()
            delegate?.tabBarDidGroupAllTabs(selectedIndices)
        } else {
            selectTab(at: index)
        }

        updateButtonVisibility()

        // Scroll to show the newly added tab (after layout computes the new size)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToEnd()
        }
    }

    // MARK: - Scroll

    /// Scrolls the tab scroll view to the trailing end so the last tab
    /// and action buttons (+, group, arrangement) are visible.
    private func scrollToEnd() {
        guard let documentView = tabScrollView.documentView else { return }
        if orientation == .horizontal {
            let maxX = max(0, documentView.frame.width - tabScrollView.contentView.bounds.width)
            tabScrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
        } else {
            let maxY = max(0, documentView.frame.height - tabScrollView.contentView.bounds.height)
            tabScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        }
        tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
    }

    /// Scrolls the minimum amount to make the tab at the given index fully visible.
    func scrollToTab(at index: Int) {
        guard index >= 0, index < tabItems.count, orientation == .horizontal else { return }
        let tabFrame = tabItems[index].frame
        let visibleRect = tabScrollView.contentView.bounds

        if tabFrame.minX < visibleRect.minX {
            // Tab is off the left edge — scroll left
            tabScrollView.contentView.scroll(to: NSPoint(x: tabFrame.minX, y: 0))
            tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
        } else if tabFrame.maxX > visibleRect.maxX {
            // Tab is off the right edge — scroll right
            let x = tabFrame.maxX - visibleRect.width
            tabScrollView.contentView.scroll(to: NSPoint(x: x, y: 0))
            tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
        }
    }

    /// Handles a tab click — behavior depends on grouped state.
    private func handleTabClick(at index: Int) {
        if isGrouped {
            // While grouped, clicking a tab just changes focus within the split
            selectedIndex = index
            delegate?.tabBarDidFocusTab(at: index)
        } else {
            selectTab(at: index)
        }
    }

    /// Select a single tab (ungrouped mode). Notifies delegate to show single terminal.
    private func selectTab(at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        selectedIndex = index
        selectedIndices = [index]
        updateSelectionAppearance()
        setFocusedTab(at: index)
        scrollToTab(at: index)
        delegate?.tabBarDidSelectTab(at: index)
    }

    /// Visually selects a tab without firing the delegate callback.
    /// Use when the caller is already handling the mode/content switch itself.
    func selectTabVisually(at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        selectedIndex = index
        selectedIndices = [index]
        updateSelectionAppearance()
        setFocusedTab(at: index)
        scrollToTab(at: index)
    }

    /// Remove tab at the given index.
    private func closeTab(at index: Int) {
        guard tabItems.count > 1 || allowCloseLastTab else { return }

        // Delegate-managed close: fire the callback and let the delegate call
        // removeTab(at:) when ready (after async confirmation, etc.)
        if delegateHandlesClose {
            delegate?.tabBarDidCloseTab(at: index)
            return
        }

        delegate?.tabBarDidCloseTab(at: index)

        removeTabItem(at: index)
    }

    /// Removes the visual tab at the given index and updates selection.
    /// Called internally after closeTab, or externally when delegateHandlesClose is true.
    func removeTab(at index: Int) {
        removeTabItem(at: index)
    }

    /// Internal helper that removes the tab item view and re-indexes.
    private func removeTabItem(at index: Int) {
        guard index < tabItems.count else { return }

        let tabItem = tabItems.remove(at: index)
        stackView.removeArrangedSubview(tabItem)
        tabItem.removeFromSuperview()

        // Re-index remaining tabs
        for (i, item) in tabItems.enumerated() {
            item.index = i
        }

        if tabItems.isEmpty {
            selectedIndex = 0
            selectedIndices = []
            updateButtonVisibility()
            return
        }

        if isGrouped {
            // Stay grouped with remaining tabs
            selectedIndices = Set(0..<tabItems.count)
            selectedIndex = min(index, tabItems.count - 1)

            // Auto-ungroup if only 1 tab remains
            if tabItems.count < 2 {
                isGrouped = false
                selectedIndices = [selectedIndex]
            }
        } else {
            // Remap single selection after removal
            if selectedIndex >= tabItems.count {
                selectedIndex = tabItems.count - 1
            }
            selectedIndices = [selectedIndex]
        }

        updateSelectionAppearance()
        updateButtonVisibility()

        if isGrouped {
            delegate?.tabBarDidGroupAllTabs(selectedIndices)
        } else {
            delegate?.tabBarDidSelectTab(at: selectedIndex)
        }
    }

    // MARK: - Selection Appearance

    /// Updates the visual state of all tab items based on current selection.
    private func updateSelectionAppearance() {
        for (i, item) in tabItems.enumerated() {
            item.setSelected(selectedIndices.contains(i))
        }
    }

    /// Shows/hides the group and arrangement buttons based on tab count and grouped state.
    /// Rebuilds layout so the trailing/bottom chain stays flush with no gaps.
    private func updateButtonVisibility() {
        let groupWasHidden = groupButton.isHidden
        let arrangementWasHidden = arrangementButton.isHidden

        groupButton.isHidden = !supportsGrouping || tabItems.count < 2
        arrangementButton.isHidden = !isGrouped

        // Rebuild layout if visibility changed so button chain stays tight
        if groupButton.isHidden != groupWasHidden || arrangementButton.isHidden != arrangementWasHidden {
            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints.removeAll()
            switch orientation {
            case .horizontal: applyHorizontalLayout()
            case .vertical:   applyVerticalLayout()
            }
        }
    }

    /// Update the title of a tab.
    func updateTabTitle(_ title: String, at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        tabItems[index].updateTitle(title)
    }

    // MARK: - Focus

    /// Marks a single tab as focused (thick accent border). Clears focus on all others.
    /// In non-grouped mode this is the selected tab. In grouped mode it's the active pane.
    func setFocusedTab(at index: Int) {
        for (i, item) in tabItems.enumerated() {
            item.setFocused(i == index)
        }
    }

    // MARK: - Highlight

    /// Set a highlight color wash on the tab at the given index.
    /// Pass nil to clear the highlight.
    func setHighlightColor(_ color: NSColor?, at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        tabItems[index].setHighlightColor(color)
    }

    // MARK: - Spinner

    /// Start the spinner on the tab at the given index.
    func startSpinner(at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        tabItems[index].startSpinner()
    }

    /// Stop the spinner on the tab at the given index.
    func stopSpinner(at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        tabItems[index].stopSpinner()
    }

    // MARK: - Font

    /// Re-applies the active font to all tab items and the add button.
    func applyFont() {
        addButton.font = FontManager.shared.activeFont.withSize(14)
        for item in tabItems {
            item.applyFont()
        }
    }

    /// Watches FontManager for changes and re-applies fonts.
    func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.startObservingFont()
            }
        }
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        for button in [addButton, groupButton, arrangementButton, orientationButton] where !button.isHidden {
            let rect = convert(button.bounds, from: button)
            addTrackingArea(NSTrackingArea(
                rect: rect,
                options: [.cursorUpdate, .activeInActiveApp],
                owner: self
            ))
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    // MARK: - Theme

    /// Applies the active theme to the tab bar background and all tab items.
    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = drawsOwnBackground
            ? theme.chromeBackground.cgColor
            : NSColor.clear.cgColor
        needsDisplay = true

        // Re-apply appearance on all tab items based on current selection set
        updateSelectionAppearance()
    }

    /// Watches ThemeManager for changes and re-applies colors.
    func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.startObservingTheme()
            }
        }
    }

    // MARK: - Orientation Toggle

    /// SF Symbol name reflecting the current tab orientation.
    /// Shows what the layout currently looks like so the user can identify the state.
    private var orientationSymbolName: String {
        switch orientation {
        case .horizontal: return "rectangle.topthird.inset.filled"
        case .vertical:   return "rectangle.leadingthird.inset.filled"
        }
    }

    /// Updates the orientation toggle button icon to reflect the current orientation.
    func updateOrientationButtonIcon() {
        orientationButton.image = NSImage(
            systemSymbolName: orientationSymbolName,
            accessibilityDescription: "Toggle tab orientation"
        )
    }

    // MARK: - Actions

    @objc private func addButtonClicked() {
        delegate?.tabBarDidRequestNewTab()
    }

    /// Toggles grouping — shows all tabs simultaneously or collapses to single tab.
    @objc private func groupButtonClicked() {
        isGrouped.toggle()

        if isGrouped {
            // Select all tabs
            selectedIndices = Set(0..<tabItems.count)
            updateSelectionAppearance()
            updateButtonVisibility()
            delegate?.tabBarDidGroupAllTabs(selectedIndices)
        } else {
            // Collapse to the focused tab
            selectedIndices = [selectedIndex]
            updateSelectionAppearance()
            updateButtonVisibility()
            delegate?.tabBarDidUngroupTabs(focusedIndex: selectedIndex)
        }
    }

    /// Cycles arrangement mode: vertical → horizontal → grid → vertical.
    @objc private func arrangementButtonClicked() {
        arrangementMode = arrangementMode.next(panelCount: selectedIndices.count)

        // Persist across sessions
        UserDefaults.standard.set(arrangementMode.rawValue, forKey: ArrangementMode.defaultsKey)

        // Update icon to reflect current arrangement
        arrangementButton.image = NSImage(
            systemSymbolName: arrangementMode.symbolName,
            accessibilityDescription: "Cycle split arrangement"
        )
        delegate?.tabBarDidChangeArrangement(arrangementMode)
    }

    /// Toggles tab bar orientation between horizontal and vertical.
    @objc private func orientationButtonClicked() {
        delegate?.tabBarDidToggleOrientation()
    }
}
