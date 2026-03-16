// RootSplitViewController.swift
// Three-column NSSplitViewController. Column order is driven by LayoutConfiguration.
// All dividers are draggable. Supports snap-to-layout presets via applyLayout().

import AppKit

@MainActor
final class RootSplitViewController: NSSplitViewController, PanelShiftDelegate {

    private var configuration: LayoutConfiguration

    private var hasAppliedInitialProportions = false

    /// Maps each panel type to its NSSplitViewItem for snap layout collapse/expand.
    private var panelItems: [PanelType: NSSplitViewItem] = [:]

    /// Called when the user manually drags a divider (not via a snap preset).
    var onManualResize: (() -> Void)?

    /// Called after column order changes (swap, custom layout, etc.).
    /// Panels observe this to update their shift arrow visibility.
    var onColumnOrderChanged: (() -> Void)?

    /// Tracks whether a programmatic layout change is in progress.
    /// Prevents manual-resize callback from firing during snap animations.
    private var isApplyingLayout = false


    // MARK: - Focus Tracking

    /// The view controller that currently has focus. Any panel or sub-pane can be focused.
    /// Clicking anywhere in a panel focuses it; Tab cycles through visible panels.
    private(set) var focusedViewController: NSViewController?

    /// Opacity applied to unfocused panels — subtle hint, not disabled.
    private static let unfocusedAlpha: CGFloat = 0.75

    /// Local event monitor for click-to-focus across all panels.
    /// `nonisolated(unsafe)` allows cleanup in deinit (nonisolated in Swift 6).
    nonisolated(unsafe) private var mouseMonitor: Any?

    /// Local event monitor for Ctrl+Tab / Ctrl+Shift+Tab focus cycling.
    /// Intercepts before AppKit's default Ctrl+Tab window switching.
    nonisolated(unsafe) private var focusCycleMonitor: Any?

    /// Local event monitor for Cmd+F to focus the find bar in the active pane.
    nonisolated(unsafe) private var findShortcutMonitor: Any?

    /// Local event monitor for Cmd+N to create a new terminal tab.
    nonisolated(unsafe) private var newTabShortcutMonitor: Any?

    /// Local event monitor for Cmd+=/-/0 to zoom image/PDF previews.
    nonisolated(unsafe) private var zoomShortcutMonitor: Any?

    // MARK: - Minimum widths per panel

    private static let minWidths: [PanelType: CGFloat] = [
        .terminal: 200,
        .explorer: 300,
        .preview:  250
    ]

    // MARK: - Holding priorities
    // All panels share the same holding priority so every divider resizes
    // the two panels it borders equally, regardless of column order.

    private static let holdingPriority = NSLayoutConstraint.Priority(250)

    // MARK: - Init

    init(configuration: LayoutConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    /// Sets up the themed split view and adds all panel items before the view
    /// hierarchy is fully constructed. NSSplitViewController requires splitView
    /// to be assigned before the view loads, and _setupSplitView (called by
    /// super.viewDidLoad) requires items to already be present.
    override func loadView() {
        let themedSV = ThemedSplitView()
        themedSV.isVertical = true
        themedSV.wantsLayer = true
        splitView = themedSV
        super.loadView()
    }

    override func viewDidLoad() {
        // Add all split view items BEFORE super.viewDidLoad(), because
        // super calls _setupSplitView which expects items to exist.
        var explorerVC: DualPaneExplorerViewController?
        var previewVC: PreviewContainerViewController?

        for panelType in configuration.columnOrder {
            let viewController = makeViewController(for: panelType)
            let item = NSSplitViewItem(viewController: viewController)

            item.minimumThickness = Self.minWidths[panelType] ?? 200
            item.holdingPriority = Self.holdingPriority
            item.canCollapse = true
            item.isCollapsed = !configuration.isVisible(panelType)

            addSplitViewItem(item)
            panelItems[panelType] = item

            if let vc = viewController as? DualPaneExplorerViewController { explorerVC = vc }
            if let vc = viewController as? PreviewContainerViewController { previewVC = vc }
        }

        super.viewDidLoad()

        // Wire file selection in explorer to preview panel
        if let explorer = explorerVC, let preview = previewVC {
            explorer.wireSelectionDelegate(preview)
        }

        applyTheme()
        startObservingTheme()

        // Observe divider drags to detect manual resizes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        // Single event monitor detects clicks across all panels — terminal, file panes, preview.
        // Hit-tests against each focusable panel's view to determine which was clicked.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleFocusClick(event)
            return event
        }

        // Ctrl+Tab / Ctrl+Shift+Tab to cycle focus between visible panes.
        // Uses a local event monitor to intercept before AppKit's default Ctrl+Tab behavior.
        installFocusCycleMonitor()
        installFindShortcutMonitor()
        installNewTabShortcutMonitor()
        installZoomShortcutMonitor()

        // Default focus: first visible focusable panel (typically top file pane)
        if let firstPanel = focusablePanels().first {
            setFocusedViewController(firstPanel)
        }

        // Navigate the top file pane when a terminal tab is double-clicked
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTerminalTabNavigate),
            name: .terminalTabDidRequestNavigate,
            object: nil
        )

        // Wire shift delegate on all panels and set initial arrow visibility
        wireShiftDelegates()
        updateAllShiftArrows()
    }

    deinit {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = focusCycleMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = findShortcutMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = newTabShortcutMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = zoomShortcutMonitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasAppliedInitialProportions {
            hasAppliedInitialProportions = true
            equalizeVisiblePanels()
        }
    }

    // MARK: - Snap Layout

    /// Applies a snap layout preset by collapsing/expanding panels
    /// and equalizing widths among visible panels.
    func applyLayout(_ layout: SnapLayout) {
        isApplyingLayout = true

        // Set collapse state synchronously to avoid timing races
        // (async animation completion + Task scheduling can leave panels
        // at minimum width for one or more frames).
        for panelType in configuration.columnOrder {
            guard let item = panelItems[panelType] else { continue }
            let shouldBeVisible = layout.visiblePanels.contains(panelType)
            item.isCollapsed = !shouldBeVisible
        }

        splitView.adjustSubviews()
        equalizeVisiblePanels()

        // Force full redraw to clear divider artifacts from the previous layout.
        // NSSplitView doesn't invalidate old divider positions when panels collapse.
        splitView.needsDisplay = true
        for item in splitViewItems {
            item.viewController.view.needsDisplay = true
            item.viewController.view.needsLayout = true
        }

        isApplyingLayout = false
        updateAllShiftArrows()
    }

    // MARK: - Custom Layout Restore

    /// Applies a full custom layout: column reorder, visibility, and width ratios.
    func applyCustomLayout(_ layout: CustomLayout) {
        isApplyingLayout = true

        // Reorder columns if the saved order differs from current.
        if layout.columnOrder != configuration.columnOrder {
            reorderColumns(to: layout.columnOrder)
        }

        // Set collapse state synchronously
        for panelType in configuration.columnOrder {
            guard let item = panelItems[panelType] else { continue }
            let shouldBeVisible = layout.panelVisibility[panelType] ?? true
            item.isCollapsed = !shouldBeVisible
        }

        splitView.adjustSubviews()
        applyWidthRatios(layout.panelWidthRatios)

        splitView.needsDisplay = true
        for item in splitViewItems {
            item.viewController.view.needsDisplay = true
            item.viewController.view.needsLayout = true
        }

        isApplyingLayout = false
        updateAllShiftArrows()
    }

    /// Removes all split view items and re-inserts them in the new column order.
    /// Preserves existing child view controllers (no terminal sessions lost).
    func reorderColumns(to newOrder: [PanelType]) {
        isApplyingLayout = true

        // Remove all items (does not destroy the VCs)
        for item in Array(splitViewItems) {
            removeSplitViewItem(item)
        }

        // Re-insert in new order
        for panelType in newOrder {
            guard let item = panelItems[panelType] else { continue }
            addSplitViewItem(item)
        }

        // Update stored column order and persist
        configuration.columnOrder = newOrder
        LayoutConfiguration.saveColumnOrder(newOrder)

        // Re-wire explorer-to-preview selection delegate
        if let explorer = explorerContainer,
           let preview = splitViewItems.lazy
               .compactMap({ $0.viewController as? PreviewContainerViewController })
               .first {
            explorer.wireSelectionDelegate(preview)
        }

        // Force relayout and equalize panel widths after reorder
        splitView.adjustSubviews()
        equalizeVisiblePanels()
        updateAllShiftArrows()

        isApplyingLayout = false
    }

    /// Sets divider positions from saved relative width ratios.
    private func applyWidthRatios(_ ratios: [PanelType: CGFloat]) {
        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return }

        // Build cumulative positions from ratios in column order
        var cumulativeX: CGFloat = 0
        for i in 0..<(splitViewItems.count - 1) {
            let panelType = configuration.columnOrder[i]
            guard let item = panelItems[panelType], !item.isCollapsed else { continue }
            let ratio = ratios[panelType] ?? (1.0 / CGFloat(splitViewItems.filter { !$0.isCollapsed }.count))
            cumulativeX += totalWidth * ratio
            splitView.setPosition(cumulativeX, ofDividerAt: i)
        }
    }

    // MARK: - Manual Resize Detection

    @objc private func splitViewDidResize(_ notification: Notification) {
        guard !isApplyingLayout, hasAppliedInitialProportions else { return }
        onManualResize?()
    }

    // MARK: - Panel Factory

    /// Creates the appropriate view controller for each panel type.
    private func makeViewController(for panelType: PanelType) -> NSViewController {
        switch panelType {
        case .terminal:
            return TerminalContainerViewController(
                tabOrientation: configuration.terminalTabOrientation
            )
        case .explorer:
            return DualPaneExplorerViewController()
        case .preview:
            return PreviewContainerViewController()
        }
    }

    // MARK: - Terminal Access

    /// Returns the TerminalContainerViewController from the split view children.
    /// Used for routing URL scheme events to the correct terminal tab.
    var terminalContainer: TerminalContainerViewController? {
        splitViewItems.lazy
            .compactMap { $0.viewController as? TerminalContainerViewController }
            .first
    }

    // MARK: - Terminal Tab Navigation

    @objc private func handleTerminalTabNavigate(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        explorerContainer?.topPane.activePanel?.viewModel.navigateTo(url)
    }

    // MARK: - Current State (for custom layout capture)

    /// Returns the current column order.
    var currentColumnOrder: [PanelType] {
        configuration.columnOrder
    }

    /// Returns collapsed state for each panel.
    func currentPanelVisibility() -> [PanelType: Bool] {
        var result: [PanelType: Bool] = [:]
        for (panelType, item) in panelItems {
            result[panelType] = !item.isCollapsed
        }
        return result
    }

    /// Returns relative width ratios (0–1) for each visible panel.
    /// Collapsed panels are excluded from the ratios.
    func currentPanelWidthRatios() -> [PanelType: CGFloat] {
        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return [:] }

        var ratios: [PanelType: CGFloat] = [:]
        for panelType in configuration.columnOrder {
            guard let item = panelItems[panelType], !item.isCollapsed else { continue }
            let width = item.viewController.view.frame.width
            ratios[panelType] = width / totalWidth
        }
        return ratios
    }

    // MARK: - Explorer Access

    /// Returns the DualPaneExplorerViewController from the split view children.
    var explorerContainer: DualPaneExplorerViewController? {
        splitViewItems.lazy
            .compactMap { $0.viewController as? DualPaneExplorerViewController }
            .first
    }

    // MARK: - Preview Access

    /// Returns the PreviewContainerViewController from the split view children.
    /// Used for programmatic preview updates (e.g., terminal file path clicks).
    var previewContainer: PreviewContainerViewController? {
        splitViewItems.lazy
            .compactMap { $0.viewController as? PreviewContainerViewController }
            .first
    }

    // MARK: - Proportions

    /// Equalizes width among all non-collapsed panels.
    private func equalizeVisiblePanels() {
        let totalWidth = splitView.bounds.width
        let visibleItems = splitViewItems.filter { !$0.isCollapsed }
        let count = visibleItems.count
        guard count > 1 else { return }

        // Calculate divider positions for equal widths
        let columnWidth = totalWidth / CGFloat(count)
        var visibleIndex = 0
        for i in 0..<(splitViewItems.count - 1) {
            // Only set position at dividers between visible items
            let leftCollapsed = splitViewItems[i].isCollapsed
            let rightCollapsed = splitViewItems[i + 1].isCollapsed
            if !leftCollapsed {
                visibleIndex += 1
            }
            if !leftCollapsed || !rightCollapsed {
                splitView.setPosition(columnWidth * CGFloat(visibleIndex), ofDividerAt: i)
            }
        }
    }

    // MARK: - Focus Management

    /// A focusable target — either a view controller (file pane, preview, terminal container)
    /// or a specific terminal pane identified by its session index within the terminal container.
    enum FocusTarget {
        case viewController(NSViewController)
        case terminalPane(index: Int, container: TerminalContainerViewController)
    }

    /// Returns all individually focusable targets in visual order.
    /// - Explorer: top and bottom file panes are listed separately.
    /// - Terminal: when multiple panes are visible (Cmd+click multi-select), each pane
    ///   is a separate target. Single-pane terminal is one target.
    /// - Collapsed (hidden) panels are excluded.
    private func focusableTargets() -> [FocusTarget] {
        var targets: [FocusTarget] = []

        for panelType in configuration.columnOrder {
            guard let item = panelItems[panelType], !item.isCollapsed else { continue }

            switch panelType {
            case .terminal:
                if let terminal = item.viewController as? TerminalContainerViewController {
                    let panes = terminal.visibleTerminalPanes()
                    if panes.isEmpty {
                        // Single terminal pane — treat container as one target
                        targets.append(.viewController(terminal))
                    } else {
                        // Multiple terminal panes — each is a separate target
                        for pane in panes {
                            targets.append(.terminalPane(index: pane.index, container: terminal))
                        }
                    }
                }
            case .explorer:
                if let explorer = item.viewController as? DualPaneExplorerViewController {
                    targets.append(.viewController(explorer.topPane))
                    targets.append(.viewController(explorer.bottomPane))
                }
            case .preview:
                targets.append(.viewController(item.viewController))
            }
        }

        return targets
    }

    /// Returns all individually focusable panels in visual order.
    /// Convenience accessor that extracts view controllers from focus targets.
    /// Used by click-to-focus and focus appearance dimming.
    private func focusablePanels() -> [NSViewController] {
        focusableTargets().compactMap { target in
            switch target {
            case .viewController(let vc): return vc
            case .terminalPane(_, let container): return container
            }
        }
    }

    /// Determines which focusable panel was clicked and updates focus state.
    private func handleFocusClick(_ event: NSEvent) {
        guard let window = view.window, event.window === window else { return }

        for panel in focusablePanels() {
            let location = panel.view.convert(event.locationInWindow, from: nil)
            if panel.view.bounds.contains(location) {
                setFocusedViewController(panel)
                return
            }
        }
    }

    /// Updates the focused panel and applies dimming to all unfocused panels.
    /// Skips redundant updates when the panel is already focused.
    func setFocusedViewController(_ vc: NSViewController) {
        guard focusedViewController !== vc else { return }
        focusedViewController = vc
        applyFocusAppearance()
    }

    /// Sets full opacity on the focused panel and dims unfocused panels.
    /// Only the content area is dimmed — tab bar rows stay at full opacity
    /// so all panels have a uniform chrome appearance.
    private func applyFocusAppearance() {
        for panel in focusablePanels() {
            let alpha: CGFloat = (panel === focusedViewController) ? 1.0 : Self.unfocusedAlpha
            let contentView = dimmableContentView(for: panel)
            // Reset the panel view to full opacity and dim only the content
            panel.view.alphaValue = 1.0
            contentView.alphaValue = alpha
        }
    }

    /// Returns the content view to dim for a given panel, excluding the tab bar row.
    private func dimmableContentView(for panel: NSViewController) -> NSView {
        if let explorer = panel as? TabbedFilePaneViewController {
            return explorer.contentView
        }
        if let preview = panel as? PreviewContainerViewController {
            return preview.contentArea
        }
        if let terminal = panel as? TerminalContainerViewController {
            return terminal.contentArea
        }
        // Fallback: dim the whole view
        return panel.view
    }

    // MARK: - Cmd+F Find Shortcut

    /// Installs a local event monitor for Cmd+F to focus the find/search bar
    /// in whichever pane currently has focus. Routes to the appropriate handler
    /// based on the focused view controller type.
    private func installFindShortcutMonitor() {
        findShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            // Only handle Cmd+F (no extra modifiers like Shift or Option)
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  event.charactersIgnoringModifiers == "f" else { return event }

            if let terminal = self.focusedViewController as? TerminalContainerViewController {
                terminal.focusFindBar()
                return nil
            }

            if let filePane = self.focusedViewController as? TabbedFilePaneViewController {
                filePane.activePanel?.activateSearchMode()
                return nil
            }

            if let preview = self.focusedViewController as? PreviewContainerViewController {
                preview.focusFindBar()
                return nil
            }

            return event
        }
    }

    // MARK: - Cmd+N New Terminal Tab

    /// Installs a local event monitor for Cmd+N to create a new terminal tab
    /// when the terminal pane is focused.
    private func installNewTabShortcutMonitor() {
        newTabShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  event.charactersIgnoringModifiers == "n" else { return event }

            if let terminal = self.focusedViewController as? TerminalContainerViewController {
                terminal.tabBarDidRequestNewTab()
                return nil
            }

            return event
        }
    }

    // MARK: - Cmd+=/-/0 Preview Zoom

    /// Installs a local event monitor for Cmd+=, Cmd+-, Cmd+0 to zoom
    /// image/PDF previews when the preview pane is focused.
    private func installZoomShortcutMonitor() {
        zoomShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option) else { return event }

            if let preview = self.focusedViewController as? PreviewContainerViewController {
                if preview.handleZoomKeyEquivalent(event) {
                    return nil
                }
            }

            return event
        }
    }

    // MARK: - Ctrl+Tab Focus Cycling

    /// Installs a local event monitor for Ctrl+Tab / Ctrl+Shift+Tab to cycle
    /// focus between visible panes. Uses a local monitor to intercept before
    /// AppKit's default Ctrl+Tab window/tab switching behavior.
    private func installFocusCycleMonitor() {
        focusCycleMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            // Only handle Tab key (keyCode 48) with Control modifier
            guard event.keyCode == 48,
                  event.modifierFlags.contains(.control) else { return event }

            let reverse = event.modifierFlags.contains(.shift)
            self.cycleFocus(reverse: reverse)

            // Consume the event — don't pass to AppKit's default handler
            return nil
        }
    }

    /// Advances (or retreats) focus through all visible focusable targets.
    /// Terminal panes with multiple visible sessions are enumerated individually.
    private func cycleFocus(reverse: Bool) {
        let targets = focusableTargets()
        guard targets.count > 1 else { return }

        // Find the current target index by matching against focusedViewController
        let currentIndex = targets.firstIndex { target in
            switch target {
            case .viewController(let vc):
                return vc === focusedViewController
            case .terminalPane(let idx, let container):
                // Match if the terminal container is focused and this is the focused pane
                return container === focusedViewController
                    && container.visibleTerminalPanes().contains { $0.index == idx }
                    && idx == findFocusedTerminalIndex(in: container)
            }
        } ?? 0

        // Advance or retreat with wraparound
        let nextIndex: Int
        if reverse {
            nextIndex = (currentIndex - 1 + targets.count) % targets.count
        } else {
            nextIndex = (currentIndex + 1) % targets.count
        }

        applyFocusTarget(targets[nextIndex])
    }

    /// Returns the currently focused terminal pane index within a container.
    private func findFocusedTerminalIndex(in container: TerminalContainerViewController) -> Int? {
        // The container's visibleTerminalPanes includes all on-screen panes.
        // The focused one is the one whose drop view has full opacity (1.0).
        for pane in container.visibleTerminalPanes() {
            if pane.view.alphaValue == 1.0 { return pane.index }
        }
        return nil
    }

    /// Applies focus to a specific target — updates focus tracking, first responder,
    /// and internal terminal state as needed.
    private func applyFocusTarget(_ target: FocusTarget) {
        switch target {
        case .viewController(let vc):
            setFocusedViewController(vc)

            // Move keyboard focus to the target panel's primary interactive view
            if let filePane = vc as? TabbedFilePaneViewController,
               let fileList = filePane.activePanel?.view.subviews
                   .compactMap({ ($0 as? NSScrollView)?.documentView as? NSTableView })
                   .first {
                view.window?.makeFirstResponder(fileList)
            } else {
                view.window?.makeFirstResponder(vc.view)
            }

        case .terminalPane(let index, let container):
            // Focus the terminal container at the root level
            setFocusedViewController(container)
            // Then focus the specific pane within the terminal container
            container.focusTerminalPane(at: index)
        }
    }

    // MARK: - Panel Shift (Swap)

    // MARK: - PanelShiftDelegate

    func shiftPanel(_ panel: PanelType, direction: PanelShiftDirection) {
        swapPanel(panel, direction: direction)
    }

    /// Swaps a panel with its visible neighbor in the given direction.
    /// Updates column order, persists it, and notifies observers.
    func swapPanel(_ panel: PanelType, direction: PanelShiftDirection) {
        let visibleOrder = configuration.columnOrder.filter { panelType in
            panelItems[panelType].map { !$0.isCollapsed } ?? false
        }

        guard let visibleIndex = visibleOrder.firstIndex(of: panel) else { return }

        // Determine the neighbor to swap with
        let neighborVisibleIndex: Int
        switch direction {
        case .left:
            guard visibleIndex > 0 else { return }
            neighborVisibleIndex = visibleIndex - 1
        case .right:
            guard visibleIndex < visibleOrder.count - 1 else { return }
            neighborVisibleIndex = visibleIndex + 1
        }

        let neighbor = visibleOrder[neighborVisibleIndex]

        // Compute new full column order by swapping the two panels
        var newOrder = configuration.columnOrder
        guard let fullIndexA = newOrder.firstIndex(of: panel),
              let fullIndexB = newOrder.firstIndex(of: neighbor) else { return }
        newOrder.swapAt(fullIndexA, fullIndexB)

        reorderColumns(to: newOrder)
        onColumnOrderChanged?()
        updateAllShiftArrows()
    }

    /// Returns the visible (non-collapsed) panels in column order.
    func visiblePanelsInOrder() -> [PanelType] {
        configuration.columnOrder.filter { panelType in
            panelItems[panelType].map { !$0.isCollapsed } ?? false
        }
    }

    /// Computes shift arrow state for each panel type.
    /// Returns a dictionary mapping each panel to its arrow config.
    func shiftArrowStates() -> [PanelType: ShiftArrowState] {
        let visible = visiblePanelsInOrder()
        var result: [PanelType: ShiftArrowState] = [:]

        for (i, panel) in visible.enumerated() {
            let showLeft = i > 0
            let showRight = i < visible.count - 1
            let leftNeighbor = showLeft ? visible[i - 1] : nil
            let rightNeighbor = showRight ? visible[i + 1] : nil
            result[panel] = ShiftArrowState(
                showLeft: showLeft,
                showRight: showRight,
                leftTooltip: leftNeighbor.map { "Swap with \($0.displayName)" },
                rightTooltip: rightNeighbor.map { "Swap with \($0.displayName)" }
            )
        }

        // Hidden panels get no arrows
        for panel in configuration.columnOrder where result[panel] == nil {
            result[panel] = ShiftArrowState(showLeft: false, showRight: false,
                                            leftTooltip: nil, rightTooltip: nil)
        }

        return result
    }

    /// Sets `self` as the shift delegate on all panel controllers.
    private func wireShiftDelegates() {
        terminalContainer?.shiftDelegate = self
        explorerContainer?.topPane.shiftDelegate = self
        previewContainer?.shiftDelegate = self
    }

    /// Pushes current shift arrow visibility to all panel controllers.
    func updateAllShiftArrows() {
        let states = shiftArrowStates()

        if let terminal = terminalContainer, let state = states[.terminal] {
            terminal.updateShiftArrows(state)
        }
        if let explorer = explorerContainer, let state = states[.explorer] {
            explorer.topPane.updateShiftArrows(state)
        }
        if let preview = previewContainer, let state = states[.preview] {
            preview.updateShiftArrows(state)
        }
    }

    // MARK: - Theme

    /// Applies the active theme to the split view dividers.
    private func applyTheme() {
        splitView.needsDisplay = true
    }

    /// Watches ThemeManager for changes and re-applies divider color.
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

// Note: NSSplitViewController manages its own delegate and uses constraint-based layout.
// Minimum widths are enforced via NSSplitViewItem.minimumThickness (set in viewDidLoad).
// Do NOT override NSSplitViewDelegate methods here — it breaks autolayout.
