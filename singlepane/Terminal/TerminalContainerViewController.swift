// TerminalContainerViewController.swift
// Hosts the custom TabBarView + terminal content area.
// Wires tab bar events to TerminalSessionManager.

import AppKit
import SwiftTerm

extension Notification.Name {
    /// Posted when the user double-clicks a terminal tab.
    /// The notification's `object` is the directory URL to navigate to.
    static let terminalTabDidRequestNavigate = Notification.Name("terminalTabDidRequestNavigate")
}

@MainActor
final class TerminalContainerViewController: NSViewController, TabBarDelegate,
    LocalProcessTerminalViewDelegate
{

    // MARK: - Properties

    private var tabOrientation: TabOrientation
    private let tabBar: TabBarView
    private let findBar = TerminalFindBarView()

    /// Stored container-level constraints — deactivated on orientation change.
    private var containerConstraints: [NSLayoutConstraint] = []

    // MARK: - Vertical Tab Bar Resize

    /// Width constraint for the tab bar in vertical mode. Updated by drag handle.
    private var tabBarWidthConstraint: NSLayoutConstraint?

    /// Drag handle on the right edge of the vertical tab bar for resizing.
    private let tabBarResizeHandle = TabBarResizeHandle()

    /// Minimum width for the vertical tab bar.
    private static let minTabBarWidth: CGFloat = 80

    /// Maximum width for the vertical tab bar.
    private static let maxTabBarWidth: CGFloat = 300

    /// UserDefaults key for persisting the vertical tab bar width.
    private static let tabBarWidthKey = "terminalVerticalTabBarWidth"

    /// Default width for the vertical tab bar.
    private static let defaultTabBarWidth: CGFloat = 120

    /// Content area container — holds either a single terminal or a split view.
    /// Exposed for focus dimming (RootSplitViewController dims content, not the tab row).
    let contentArea = NSView()

    private var sessionManager: TerminalSessionManager!

    // MARK: - Split View

    /// The split view used when multiple terminals are displayed. Nil in single mode.
    /// In grid mode, this is the outer (row) split; inner (column) splits are stored separately.
    private var splitView: NSSplitView?

    /// Inner horizontal split views for each grid row. Empty outside grid mode.
    private var innerSplitViews: [NSSplitView] = []

    /// Container view for grid mode layout (NSStackView-based). Nil outside grid mode.
    /// Grid mode uses NSStackView instead of NSSplitView because NSStackView's
    /// .fillEqually distribution guarantees equal sizing via Auto Layout,
    /// avoiding NSSplitView's proportional redistribution issues.
    private var gridContainer: NSView?

    /// Grip overlays on split dividers (reuses DividerGripView from main layout).
    private var splitDividerGrips: [DividerGripView] = []

    /// Per-pane drop views keyed by session index. Each wraps a terminal for drag-drop.
    private var paneDropViews: [Int: TerminalDropView] = [:]

    /// How multiple terminal panes are arranged. Restored from UserDefaults.
    private var arrangementMode: ArrangementMode = {
        if let raw = UserDefaults.standard.string(forKey: ArrangementMode.defaultsKey),
           let mode = ArrangementMode(rawValue: raw) {
            return mode
        }
        return .vertical
    }()

    /// Opacity for unfocused split panes — matches RootSplitViewController convention.
    private static let unfocusedAlpha: CGFloat = 0.75

    /// Local event monitor for click-to-focus within split panes.
    nonisolated(unsafe) private var splitFocusMonitor: Any?

    // MARK: - Link Detection

    /// Local event monitor for click-to-open link detection in terminal output.
    /// `nonisolated(unsafe)` allows cleanup in deinit (nonisolated in Swift 6).
    nonisolated(unsafe) private var linkClickMonitor: Any?

    /// Local event monitor for mouseDown tracking (to distinguish clicks from drags).
    nonisolated(unsafe) private var linkMouseDownMonitor: Any?

    /// Local event monitor for hover to change cursor over links.
    nonisolated(unsafe) private var linkHoverMonitor: Any?


    /// Grid position where the last mouseDown occurred — used to distinguish
    /// a click (same position) from a drag/selection (different position).
    private var mouseDownGridPosition: (session: UUID, row: Int, col: Int)?

    /// Timer that periodically scans visible terminal rows for links.
    nonisolated(unsafe) private var linkScanTimer: Timer?

    /// Per-session link overlays — one per visible terminal pane.
    private var linkOverlays: [UUID: TerminalLinkOverlayView] = [:]

    /// Per-session exit code gutters — one per visible terminal pane.
    private var gutterViews: [UUID: TerminalGutterView] = [:]

    // MARK: - Prompt Navigation

    /// Local event monitor for Cmd+Up/Down to jump between prompts (OSC 133).
    nonisolated(unsafe) private var promptNavMonitor: Any?

    // MARK: - Hints Mode

    /// Controller for the hints/quick-select modal (Cmd+Shift+E).
    private let hintsController = TerminalHintsController()

    /// Local event monitor for the Cmd+Shift+E hotkey to activate hints mode.
    nonisolated(unsafe) private var hintsHotkeyMonitor: Any?

    // MARK: - Panel Shift

    /// Shift arrow buttons for reordering this panel relative to neighbors.
    private let shiftArrows = PanelShiftArrowView(panelType: .terminal)

    /// Delegate for panel swap requests. Set by RootSplitViewController.
    weak var shiftDelegate: PanelShiftDelegate? {
        didSet { shiftArrows.shiftDelegate = shiftDelegate }
    }

    // MARK: - Init

    init(tabOrientation: TabOrientation) {
        self.tabOrientation = tabOrientation
        self.tabBar = TabBarView()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let monitor = linkClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = linkMouseDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = linkHoverMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = splitFocusMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = promptNavMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = hintsHotkeyMonitor { NSEvent.removeMonitor(monitor) }
        linkScanTimer?.invalidate()
    }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Configure tab bar orientation
        tabBar.orientation = tabOrientation
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)

        // Find bar between tab bar and terminal content
        findBar.delegate = self
        findBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(findBar)

        // Shift arrows — trailing edge of tab bar row for panel reorder
        shiftArrows.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shiftArrows)

        // Resize handle for vertical tab bar — hidden in horizontal mode
        tabBarResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        tabBarResizeHandle.onDrag = { [weak self] deltaX in self?.handleTabBarResize(deltaX) }
        tabBarResizeHandle.isHidden = true
        container.addSubview(tabBarResizeHandle)

        // Content area — hosts either a single terminal or a split view
        contentArea.wantsLayer = true
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentArea)

        switch tabOrientation {
        case .horizontal:
            applyHorizontalLayout(container: container)
        case .vertical:
            applyVerticalLayout(container: container)
        }

        self.view = container
    }

    /// Terminal content margin — visual padding between the terminal and panel edges.
    /// Ensures both terminal text and the scrollbar have breathing room from the edge.
    private static let terminalMargin: CGFloat = 10

    private func applyHorizontalLayout(container: NSView) {
        tabBarResizeHandle.isHidden = true
        tabBarWidthConstraint = nil

        let m = Self.terminalMargin
        let constraints = [
            // Tab bar at the top — leaves trailing room for shift arrows
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            // Shift arrows — trailing edge, on top of tab bar
            shiftArrows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            shiftArrows.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),

            // Find bar below tab bar — full width, edge-to-edge
            findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBar.heightAnchor.constraint(equalToConstant: TerminalFindBarView.barHeight),

            // Content below find bar, with margin between find bar and terminal
            contentArea.topAnchor.constraint(equalTo: findBar.bottomAnchor, constant: 8),
            contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
        ]
        containerConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    private func applyVerticalLayout(container: NSView) {
        let savedWidth = UserDefaults.standard.object(forKey: Self.tabBarWidthKey) as? CGFloat
            ?? Self.defaultTabBarWidth
        let width = min(max(savedWidth, Self.minTabBarWidth), Self.maxTabBarWidth)

        let widthConstraint = tabBar.widthAnchor.constraint(equalToConstant: width)
        tabBarWidthConstraint = widthConstraint

        // Show resize handle on the right edge of the tab bar
        tabBarResizeHandle.isHidden = false

        let m = Self.terminalMargin
        let constraints = [
            // Tab bar on the left
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            widthConstraint,

            // Resize handle on the right edge of the tab bar
            tabBarResizeHandle.topAnchor.constraint(equalTo: container.topAnchor),
            tabBarResizeHandle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tabBarResizeHandle.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -2),
            tabBarResizeHandle.widthAnchor.constraint(equalToConstant: 6),

            // Shift arrows — top-right corner in vertical tab mode
            shiftArrows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            shiftArrows.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),

            // Find bar at the top of the content area — full width so background covers the strip
            findBar.topAnchor.constraint(equalTo: container.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBar.heightAnchor.constraint(equalToConstant: TerminalFindBarView.barHeight),

            // Content below find bar, with margin between find bar and terminal
            contentArea.topAnchor.constraint(equalTo: findBar.bottomAnchor, constant: 8),
            contentArea.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: m),
            contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
        ]
        containerConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    /// Adjusts the vertical tab bar width by the given delta from a drag gesture.
    private func handleTabBarResize(_ deltaX: CGFloat) {
        guard let constraint = tabBarWidthConstraint else { return }
        let newWidth = min(max(constraint.constant + deltaX, Self.minTabBarWidth), Self.maxTabBarWidth)
        constraint.constant = newWidth
        UserDefaults.standard.set(newWidth, forKey: Self.tabBarWidthKey)
    }

    /// Switches the tab bar orientation at runtime. Tears down existing container
    /// constraints and re-applies the layout for the new orientation.
    func setTabOrientation(_ orientation: TabOrientation) {
        guard orientation != tabOrientation else { return }

        // Tear down existing container layout
        NSLayoutConstraint.deactivate(containerConstraints)
        containerConstraints.removeAll()

        // Apply new orientation
        tabOrientation = orientation
        tabBar.orientation = orientation

        switch orientation {
        case .horizontal:
            applyHorizontalLayout(container: view)
        case .vertical:
            applyVerticalLayout(container: view)
        }

        view.layoutSubtreeIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sessionManager = TerminalSessionManager(containerView: contentArea)

        // Enable group-all, orientation toggle, and inline rename on terminal tabs
        tabBar.supportsGrouping = true
        tabBar.supportsOrientationToggle = true
        tabBar.supportsRename = true

        // Create the first terminal session in ~/Documents
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        createNewSession(directory: documentsURL?.path)

        // Apply initial theme/font and start observing changes
        applyTerminalTheme()
        tabBar.applyTheme()
        tabBar.startObservingTheme()
        tabBar.startObservingFont()
        observeThemeForTerminals()
        observeFontForTerminals()

        // Install link detection monitors for click-to-open and hover
        installLinkMonitors()

        // Monitor clicks for split pane focus
        installSplitFocusMonitor()

        // Cmd+Up/Down for prompt navigation (OSC 133)
        installPromptNavMonitor()

        // Cmd+Shift+E for hints/quick-select mode
        hintsController.delegate = self
        installHintsHotkeyMonitor()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Focus the active terminal once the window is available.
        // During viewDidLoad the window is nil, so makeFirstResponder is deferred here.
        if let session = sessionManager.activeSession {
            view.window?.makeFirstResponder(session.terminalView)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // When the terminal panel is resized (e.g., adjacent panes shown/hidden),
        // the layer-backed contentArea may retain stale backing store pixels.
        // Force all visible terminal views to redraw so no line artifacts remain.
        contentArea.needsDisplay = true
        for session in sessionManager.sessions {
            session.terminalView.needsDisplay = true
        }
    }

    // MARK: - Theme Observation

    /// Watches ThemeManager for changes and re-applies colors to all terminal sessions
    /// and the container background (visible as the margin color).
    private func observeThemeForTerminals() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTerminalTheme()
                self?.observeThemeForTerminals()
            }
        }
    }

    /// Applies the active theme to terminal sessions and the container background.
    private func applyTerminalTheme() {
        sessionManager.applyThemeToAllSessions()
        view.layer?.backgroundColor = ThemeManager.shared.activeTheme.backgroundColor.cgColor
    }

    // MARK: - Font Observation

    /// Watches FontManager for changes and re-applies font to all terminal sessions.
    private func observeFontForTerminals() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sessionManager.applyFontToAllSessions()
                self?.observeFontForTerminals()
            }
        }
    }

    // MARK: - Session Creation

    /// Creates a new terminal session at the given directory, switches to it, and focuses it.
    /// Called externally by the file explorer's "open terminal here" action.
    func openNewSession(directory: String) {
        createNewSession(directory: directory, focusAfterCreation: true)
    }

    private func createNewSession(directory: String? = nil, focusAfterCreation: Bool = false) {
        let session = sessionManager.createSession(directory: directory)
        session.terminalView.processDelegate = self

        // Tab title = last path component of the working directory
        let cwd = directory ?? NSHomeDirectory()
        let title = URL(fileURLWithPath: cwd).lastPathComponent
        tabBar.addTab(title: title)

        // Switch to the new tab and focus the terminal for immediate typing
        if focusAfterCreation {
            let newIndex = sessionManager.sessions.count - 1
            tabBarDidSelectTab(at: newIndex)
            tabBar.selectTabVisually(at: newIndex)

            // Walk parent chain to find RootSplitViewController and focus this panel
            var current: NSViewController? = parent
            while let vc = current {
                if let rootSplit = vc as? RootSplitViewController {
                    rootSplit.setFocusedViewController(self)
                    break
                }
                current = vc.parent
            }
        }
    }

    // MARK: - Hook Events

    /// Highlight the tab for the given session UUID with a color wash.
    /// Called by the URL scheme handler when a hook fires.
    func highlightTab(sessionID: UUID, color: NSColor?) {
        guard let index = sessionManager.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessionManager.sessions[index].hookHighlightColor = color
        tabBar.setHighlightColor(color, at: index)
        paneDropViews[index]?.setHighlightColor(color)
    }

    /// Start the spinner on the tab for the given session UUID.
    func startSpinner(sessionID: UUID) {
        guard let index = sessionManager.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        tabBar.startSpinner(at: index)
    }

    /// Stop the spinner on the tab for the given session UUID.
    func stopSpinner(sessionID: UUID) {
        guard let index = sessionManager.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        tabBar.stopSpinner(at: index)
    }

    /// Switch to the tab for the given session UUID.
    /// Used by notification click-through to navigate to the correct tab.
    func selectTab(sessionID: UUID) {
        guard let index = sessionManager.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        tabBar.selectTabVisually(at: index)
    }

    /// Returns the title of the tab for the given session UUID, or nil if not found.
    func tabTitle(forSessionID sessionID: UUID) -> String? {
        sessionManager.sessions.first(where: { $0.id == sessionID })?.title
    }

    // MARK: - Find Bar Focus

    /// Focuses the terminal find bar search field. Called by RootSplitVC on Cmd+F.
    func focusFindBar() {
        findBar.focus()
    }

    // MARK: - Text Insertion

    /// Sends text to the active terminal session (e.g., a shell-escaped file path).
    func sendToActiveSession(_ text: String) {
        sessionManager.activeSession?.terminalView.send(txt: text)
    }

    // MARK: - Shift Arrow Update

    /// Updates shift arrow visibility and tooltips from computed state.
    func updateShiftArrows(_ state: ShiftArrowState) {
        shiftArrows.update(state)
    }

    // MARK: - TabBarDelegate

    func tabBarDidSelectTab(at index: Int) {
        // Single-tab selection — collapse any split back to single pane
        tearDownSplitView()
        sessionManager.activeSession?.searchText = findBar.searchText
        sessionManager.switchTo(index)
        showSingleTerminal(at: index)
        syncFindBarForActiveSession()
        scanVisibleLinks()
    }

    func tabBarDidGroupAllTabs(_ indices: Set<Int>) {
        // Group all — show all tabs simultaneously in split/grid
        sessionManager.activeSession?.searchText = findBar.searchText
        sessionManager.showMultiple(indices: indices)
        buildSplitView(indices: indices)
        applyFocusAppearance()
        scanVisibleLinks()
    }

    func tabBarDidUngroupTabs(focusedIndex: Int) {
        // Ungroup — collapse back to the focused single tab
        tearDownSplitView()
        sessionManager.activeSession?.searchText = findBar.searchText
        sessionManager.switchTo(focusedIndex)
        showSingleTerminal(at: focusedIndex)
        syncFindBarForActiveSession()
        scanVisibleLinks()
    }

    func tabBarDidFocusTab(at index: Int) {
        // Focus a specific pane within the grouped split — no layout rebuild
        guard sessionManager.sessions.indices.contains(index) else { return }
        sessionManager.setFocused(index: index)
        view.window?.makeFirstResponder(sessionManager.sessions[index].terminalView)
        applyFocusAppearance()
    }

    func tabBarDidChangeArrangement(_ mode: ArrangementMode) {
        arrangementMode = mode

        // Rebuild the split layout with the new arrangement
        if sessionManager.visibleIndices.count > 1 {
            buildSplitView(indices: sessionManager.visibleIndices)
            applyFocusAppearance()
            scanVisibleLinks()
        }
    }

    func tabBarDidCloseTab(at index: Int) {
        sessionManager.closeSession(at: index)

        // If still in grouped mode with multiple tabs, rebuild the split
        if sessionManager.visibleIndices.count > 1 {
            buildSplitView(indices: sessionManager.visibleIndices)
        } else {
            tearDownSplitView()
            if let idx = sessionManager.visibleIndices.first {
                showSingleTerminal(at: idx)
            }
        }
    }

    func tabBarDidRequestNewTab() {
        // Inherit the CWD from the active session so the new tab starts in the same directory.
        let cwd = sessionManager.activeSession?.currentDirectory
        createNewSession(directory: cwd)
    }

    func tabBarDidToggleOrientation() {
        let newOrientation: TabOrientation = tabOrientation == .horizontal ? .vertical : .horizontal
        setTabOrientation(newOrientation)
        tabBar.updateOrientationButtonIcon()
        LayoutConfiguration.saveTerminalTabOrientation(newOrientation)
    }

    func tabBarDidDoubleClickTab(at index: Int) {
        guard sessionManager.sessions.indices.contains(index),
              let cwd = sessionManager.sessions[index].currentDirectory else { return }
        let url = URL(fileURLWithPath: cwd)
        NotificationCenter.default.post(name: .terminalTabDidRequestNavigate, object: url)
    }

    func tabBarDidRenameTab(at index: Int, newTitle: String) {
        guard sessionManager.sessions.indices.contains(index) else { return }
        let session = sessionManager.sessions[index]

        if newTitle.isEmpty {
            // Empty name reverts to directory-based title
            session.customTabTitle = nil
            let dirName = session.currentDirectory
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Terminal"
            tabBar.updateTabTitle(dirName, at: index)
        } else {
            session.customTabTitle = newTitle
            tabBar.updateTabTitle(newTitle, at: index)
        }
    }

    func tabBarDidReorderTab(from oldIndex: Int, to newIndex: Int) {
        sessionManager.moveSession(from: oldIndex, to: newIndex)

        // If grouped/split, rebuild the split layout to reflect the new order
        if sessionManager.visibleIndices.count > 1 {
            buildSplitView(indices: sessionManager.visibleIndices)
            applyFocusAppearance()
            scanVisibleLinks()
        }
    }

    // MARK: - Split View Management

    /// Displays a single terminal view (no split). Used for normal single-tab mode.
    private func showSingleTerminal(at index: Int) {
        // Remove any existing terminal subviews from contentArea
        contentArea.subviews.forEach { $0.removeFromSuperview() }
        paneDropViews.removeAll()
        gutterViews.removeAll()

        guard let session = sessionManager.activeSession else { return }
        let dropView = makeDropView(for: session, at: index)
        contentArea.addSubview(dropView)

        // Fill the content area
        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            dropView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            dropView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        session.configureScrollerStyle()
        view.window?.makeFirstResponder(session.terminalView)
    }

    /// Builds the split layout for multiple terminal sessions.
    /// Dispatches to flat (vertical/horizontal) or grid layout based on arrangementMode.
    ///
    /// Terminal views are temporarily detached during the layout rebuild to prevent
    /// SIGWINCH resize cascades. They are re-attached after equalization once all
    /// drop view frames have settled via a full view hierarchy layout pass.
    private func buildSplitView(indices: Set<Int>) {
        tearDownSplitView()
        contentArea.subviews.forEach { $0.removeFromSuperview() }
        paneDropViews.removeAll()
        gutterViews.removeAll()

        let sorted = indices.sorted()

        // Build the layout WITHOUT attaching terminal views. Terminals are
        // added in the async block below at their final sizes, avoiding
        // intermediate SIGWINCH resize cascades from wrong-sized frames.
        if arrangementMode == .grid && sorted.count > 2 {
            buildGridView(sortedIndices: sorted)
        } else {
            buildFlatSplitView(sortedIndices: sorted)
        }

        // Install divider grips for flat modes only. Grid mode locks panes
        // to equal sizes — no user-draggable dividers to avoid cross-row misalignment.
        if arrangementMode != .grid {
            installSplitDividerGrips()
        }

        // Equalize pane sizes, then re-attach terminal views at their final frames.
        // Equalization runs AFTER the initial layout pass so NSSplitView's
        // proportional redistribution doesn't undo our divider positions.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // First layout pass — let Auto Layout and NSSplitView settle.
            self.view.layoutSubtreeIfNeeded()

            // Now equalize divider positions on the settled split views.
            self.equalizeSplitPanes()

            // Second layout pass — propagate equalized divider positions
            // down to drop view frames before terminal re-attachment.
            self.view.layoutSubtreeIfNeeded()

            // Re-attach terminal views now that drop views have their final sizes.
            let gutterW = TerminalGutterView.gutterWidth
            for idx in sorted {
                guard self.sessionManager.sessions.indices.contains(idx),
                      let dropView = self.paneDropViews[idx] else { continue }
                let session = self.sessionManager.sessions[idx]
                session.terminalView.translatesAutoresizingMaskIntoConstraints = true
                session.terminalView.autoresizingMask = [.width, .height]
                session.terminalView.frame = NSRect(
                    x: gutterW,
                    y: 0,
                    width: floor(max(dropView.bounds.width - gutterW, 0)),
                    height: floor(dropView.bounds.height)
                )
                dropView.addSubview(session.terminalView)
                session.configureScrollerStyle()
            }

            // Focus the active session after re-attachment
            if let session = self.sessionManager.activeSession {
                self.view.window?.makeFirstResponder(session.terminalView)
            }
        }
    }

    /// Builds a single-axis NSSplitView for vertical or horizontal arrangement.
    private func buildFlatSplitView(sortedIndices: [Int]) {
        let sv = NSSplitView()
        sv.isVertical = (arrangementMode == .vertical)
        sv.dividerStyle = .thin
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.wantsLayer = true
        contentArea.addSubview(sv)

        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: contentArea.topAnchor),
            sv.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        for idx in sortedIndices {
            guard sessionManager.sessions.indices.contains(idx) else { continue }
            let session = sessionManager.sessions[idx]
            let dropView = makeDropView(for: session, at: idx, attachTerminal: false)
            sv.addSubview(dropView)
        }

        splitView = sv
    }

    /// Builds a 2D grid using pure Auto Layout constraints on a plain container.
    /// Each pane is directly constrained for equal height (across rows) and equal
    /// width (within each row). Last row panes stretch to fill the row width.
    /// This avoids NSSplitView's proportional redistribution and NSStackView's
    /// cross-axis sizing issues entirely.
    private func buildGridView(sortedIndices: [Int]) {
        let (cols, rows) = ArrangementMode.gridDimensions(for: sortedIndices.count)
        let spacing: CGFloat = 1

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = ThemeManager.shared.activeTheme.chromeBorder.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentArea.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        // Build drop views arranged in a 2D grid.
        var grid: [[TerminalDropView]] = []

        for row in 0..<rows {
            let start = row * cols
            let end = min(start + cols, sortedIndices.count)
            let rowIndices = Array(sortedIndices[start..<end])

            var rowViews: [TerminalDropView] = []
            for idx in rowIndices {
                guard sessionManager.sessions.indices.contains(idx) else { continue }
                let session = sessionManager.sessions[idx]
                let dropView = makeDropView(for: session, at: idx, attachTerminal: false)
                container.addSubview(dropView)
                rowViews.append(dropView)
            }
            grid.append(rowViews)
        }

        // Reference pane — all panes share its height for uniform row sizing.
        guard let referencePane = grid.first?.first else { return }

        var constraints: [NSLayoutConstraint] = []

        for (rowIdx, rowViews) in grid.enumerated() {
            for (colIdx, pane) in rowViews.enumerated() {

                // -- Vertical positioning --

                if rowIdx == 0 {
                    // First row: top edge pins to container top.
                    constraints.append(
                        pane.topAnchor.constraint(equalTo: container.topAnchor)
                    )
                } else if let abovePane = grid[rowIdx - 1].first {
                    // Subsequent rows: chain to the bottom of the previous row.
                    constraints.append(
                        pane.topAnchor.constraint(
                            equalTo: abovePane.bottomAnchor, constant: spacing
                        )
                    )
                }

                // Last row: bottom edge pins to container bottom (first pane only
                // since all panes in the row share the same height and top).
                if rowIdx == grid.count - 1 && colIdx == 0 {
                    constraints.append(
                        pane.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                    )
                }

                // Equal height: every pane matches the reference pane.
                if pane !== referencePane {
                    constraints.append(
                        pane.heightAnchor.constraint(equalTo: referencePane.heightAnchor)
                    )
                }

                // -- Horizontal positioning --

                if colIdx == 0 {
                    // First column: leading edge pins to container leading.
                    constraints.append(
                        pane.leadingAnchor.constraint(equalTo: container.leadingAnchor)
                    )
                } else {
                    // Subsequent columns: chain to previous pane's trailing edge.
                    constraints.append(
                        pane.leadingAnchor.constraint(
                            equalTo: rowViews[colIdx - 1].trailingAnchor,
                            constant: spacing
                        )
                    )
                }

                // Last column in each row: trailing edge pins to container trailing.
                if colIdx == rowViews.count - 1 {
                    constraints.append(
                        pane.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                    )
                }

                // Equal width within the row: all panes match the first pane's width.
                if colIdx > 0 {
                    constraints.append(
                        pane.widthAnchor.constraint(equalTo: rowViews[0].widthAnchor)
                    )
                }
            }
        }

        NSLayoutConstraint.activate(constraints)
        gridContainer = container
    }

    /// Removes the split view (or grid container) and cleans up divider grips.
    private func tearDownSplitView() {
        for grip in splitDividerGrips {
            grip.removeFromSuperview()
        }
        splitDividerGrips.removeAll()
        innerSplitViews.removeAll()
        splitView?.removeFromSuperview()
        splitView = nil
        gridContainer?.removeFromSuperview()
        gridContainer = nil
        linkOverlays.removeAll()
    }

    /// Distributes equal space to each pane in the split view.
    /// In grid mode, equalizes both outer rows and inner columns within each row.
    /// Inner splits are equalized after a forced layout pass so their bounds are valid.
    private func equalizeSplitPanes() {
        guard let sv = splitView else { return }

        equalizeSplitView(sv)

        // Force layout so inner splits receive their updated frames
        // before we try to equalize their dividers.
        sv.layoutSubtreeIfNeeded()

        // Equalize inner splits for grid mode
        for innerSV in innerSplitViews {
            equalizeSplitView(innerSV)
        }
    }

    /// Equalizes divider positions within a single NSSplitView.
    /// Accounts for divider thickness to produce truly equal pane sizes.
    private func equalizeSplitView(_ sv: NSSplitView) {
        let count = sv.subviews.count
        guard count > 1 else { return }

        let totalSize = sv.isVertical ? sv.bounds.width : sv.bounds.height
        let dividerTotal = sv.dividerThickness * CGFloat(count - 1)
        let paneSize = ((totalSize - dividerTotal) / CGFloat(count)).rounded(.down)

        for i in 0..<(count - 1) {
            // Position = cumulative pane widths + cumulative divider thicknesses.
            let position = paneSize * CGFloat(i + 1)
                + sv.dividerThickness * CGFloat(i)
            sv.setPosition(position, ofDividerAt: i)
        }
    }

    /// Creates a TerminalDropView wrapping a session's terminal view with drop handlers.
    /// Includes an exit code gutter on the left edge for OSC 133 command marks.
    ///
    /// When `attachTerminal` is false, the terminal view is NOT added to the drop view.
    /// Use this in multi-pane layouts where terminals are detached during layout and
    /// re-attached at their final size to avoid intermediate SIGWINCH resize cascades.
    private func makeDropView(
        for session: TerminalSession,
        at index: Int,
        attachTerminal: Bool = true
    ) -> TerminalDropView {
        let dropView = TerminalDropView(frame: contentArea.bounds)
        dropView.translatesAutoresizingMaskIntoConstraints = false

        // Exit code gutter — thin strip on the left edge of each terminal pane.
        let gutter = TerminalGutterView()
        gutter.session = session
        gutter.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(gutter)
        gutterViews[session.id] = gutter

        // Layout: gutter pinned to left edge, terminal fills the rest.
        // Use autoresizing mask for the terminal view since SwiftTerm expects it.
        NSLayoutConstraint.activate([
            gutter.topAnchor.constraint(equalTo: dropView.topAnchor),
            gutter.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            gutter.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: TerminalGutterView.gutterWidth),
        ])

        if attachTerminal {
            // Add terminal view immediately — used for single-pane mode where
            // the drop view already has its final size.
            let gutterW = TerminalGutterView.gutterWidth
            session.terminalView.translatesAutoresizingMaskIntoConstraints = true
            session.terminalView.autoresizingMask = [.width, .height]
            session.terminalView.frame = NSRect(
                x: gutterW,
                y: 0,
                width: floor(max(dropView.bounds.width - gutterW, 0)),
                height: floor(dropView.bounds.height)
            )
            dropView.addSubview(session.terminalView)
            session.configureScrollerStyle()
        }

        // Wire drop handlers to this specific session
        dropView.onFilesDropped = { [weak session] escapedPaths in
            session?.terminalView.send(txt: escapedPaths)
        }
        dropView.onFolderDropped = { [weak self] folderURL in
            // Defer to the next run loop so performDragOperation returns before
            // the view hierarchy is torn down. Without this, removing the drop
            // view during the drag operation corrupts AppKit's drag tracking
            // state and breaks subsequent mouse event delivery to the tab bar.
            DispatchQueue.main.async {
                self?.createNewSession(directory: folderURL.path, focusAfterCreation: true)
            }
        }

        paneDropViews[index] = dropView
        return dropView
    }

    /// Installs DividerGripView overlays on all terminal split dividers.
    /// Grips are added to contentArea (not the split view itself) because NSSplitView
    /// treats all direct subviews as arranged panes.
    /// In grid mode, installs grips on both outer (row) and inner (column) dividers.
    private func installSplitDividerGrips() {
        guard let sv = splitView else { return }

        // Outer dividers (horizontal dividers between rows, or the single axis in flat mode)
        installGrips(for: sv, isVerticalSplit: sv.isVertical)

        // Inner dividers for grid mode — vertical dividers within each row
        for innerSV in innerSplitViews {
            installGrips(for: innerSV, isVerticalSplit: true)

            // Reposition inner grips on inner split resize
            NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: innerSV,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.layoutSplitDividerGrips() }
            }
        }

        layoutSplitDividerGrips()

        // Reposition on outer split resize
        NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: sv,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layoutSplitDividerGrips() }
        }
    }

    /// Creates and adds grip overlays for all dividers in a single NSSplitView.
    private func installGrips(for sv: NSSplitView, isVerticalSplit: Bool) {
        let paneCount = sv.arrangedSubviews.count
        guard paneCount > 1 else { return }

        for i in 0..<(paneCount - 1) {
            let grip = DividerGripView()
            grip.isVerticalSplit = isVerticalSplit
            grip.dividerIndex = i
            contentArea.addSubview(grip)
            splitDividerGrips.append(grip)
        }
    }

    /// Positions grip overlays centered on each split divider.
    /// Grips live in contentArea, so positions are converted from split view coordinates.
    /// Handles both flat and nested (grid) split views.
    private func layoutSplitDividerGrips() {
        guard let outerSV = splitView else { return }

        // Collect all split views whose grips we need to position
        var allSplitViews: [NSSplitView] = [outerSV]
        allSplitViews.append(contentsOf: innerSplitViews)

        let thickness: CGFloat = 4
        var gripIndex = 0

        for sv in allSplitViews {
            let panes = sv.arrangedSubviews
            guard panes.count > 1 else { continue }

            for i in 0..<(panes.count - 1) {
                guard gripIndex < splitDividerGrips.count else { return }
                let grip = splitDividerGrips[gripIndex]
                gripIndex += 1

                let subviewFrame = panes[i].frame

                if sv.isVertical {
                    let dividerX = subviewFrame.maxX + sv.dividerThickness / 2
                    let converted = sv.convert(NSPoint(x: dividerX, y: 0), to: contentArea)
                    let svInContent = sv.convert(sv.bounds, to: contentArea)
                    grip.frame = NSRect(
                        x: converted.x - thickness / 2,
                        y: svInContent.minY,
                        width: thickness,
                        height: svInContent.height
                    )
                } else {
                    let dividerY = subviewFrame.maxY + sv.dividerThickness / 2
                    let converted = sv.convert(NSPoint(x: 0, y: dividerY), to: contentArea)
                    grip.frame = NSRect(
                        x: 0,
                        y: converted.y - thickness / 2,
                        width: contentArea.bounds.width,
                        height: thickness
                    )
                }
                grip.needsDisplay = true
            }
        }
    }

    // MARK: - Split Focus Management

    /// Installs a click monitor to detect which split pane the user clicks.
    private func installSplitFocusMonitor() {
        splitFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.handleSplitFocusClick(event)
            return event
        }
    }

    /// Determines which split pane was clicked and focuses it.
    private func handleSplitFocusClick(_ event: NSEvent) {
        guard sessionManager.visibleIndices.count > 1 else { return }
        guard let window = view.window, event.window === window else { return }

        for (idx, dropView) in paneDropViews {
            let point = dropView.convert(event.locationInWindow, from: nil)
            if dropView.bounds.contains(point) {
                sessionManager.setFocused(index: idx)
                view.window?.makeFirstResponder(
                    sessionManager.sessions[idx].terminalView
                )
                applyFocusAppearance()
                return
            }
        }
    }

    /// Dims unfocused split panes, highlights the focused one,
    /// and marks the corresponding tab with the accent color.
    private func applyFocusAppearance() {
        let focusedIdx = sessionManager.focusedIndex

        guard sessionManager.visibleIndices.count > 1 else {
            // Single pane — full opacity, restore hook highlights
            paneDropViews.values.forEach { $0.alphaValue = 1.0 }
            for i in 0..<sessionManager.sessions.count {
                tabBar.setHighlightColor(sessionManager.sessions[i].hookHighlightColor, at: i)
            }
            return
        }

        for (idx, dropView) in paneDropViews {
            dropView.alphaValue = (idx == focusedIdx) ? 1.0 : Self.unfocusedAlpha
        }

        // Restore each tab's hook highlight color — never override with focus color.
        for i in 0..<sessionManager.sessions.count {
            tabBar.setHighlightColor(sessionManager.sessions[i].hookHighlightColor, at: i)
        }
        tabBar.setFocusedTab(at: focusedIdx)
        tabBar.scrollToTab(at: focusedIdx)
    }

    // MARK: - Visible Pane Enumeration (for Ctrl+Tab focus cycling)

    /// Returns each currently visible terminal pane's session index and drop view,
    /// sorted by index. Used by RootSplitViewController to enumerate individual
    /// terminal panes as separate focusable targets during Ctrl+Tab cycling.
    /// Returns an empty array when only a single terminal pane is visible.
    func visibleTerminalPanes() -> [(index: Int, view: NSView)] {
        guard sessionManager.visibleIndices.count > 1 else { return [] }
        return sessionManager.visibleIndices.sorted().compactMap { idx in
            guard let dropView = paneDropViews[idx] else { return nil }
            return (index: idx, view: dropView as NSView)
        }
    }

    /// Focuses a specific terminal pane by session index.
    /// Updates the session manager's focused index, moves keyboard focus
    /// to that terminal view, and refreshes the split focus dimming.
    func focusTerminalPane(at index: Int) {
        guard sessionManager.sessions.indices.contains(index) else { return }
        sessionManager.setFocused(index: index)
        view.window?.makeFirstResponder(sessionManager.sessions[index].terminalView)
        applyFocusAppearance()
    }

    // MARK: - Tab Switching (find bar state sync)

    /// Saves the find bar state to the outgoing session and restores from the incoming session.
    private func syncFindBarForActiveSession() {
        guard let session = sessionManager.activeSession else { return }
        findBar.searchText = session.searchText
        // Re-execute search so SwiftTerm's internal state matches the restored text
        if session.searchText.isEmpty {
            session.terminalView.clearSearch()
            findBar.updateCounter(current: 0, total: 0)
        } else {
            performSearch(session.searchText)
        }
    }

    // MARK: - Search Logic (Global across visible panes)

    /// Executes a search across all visible terminal sessions and updates the counter.
    private func performSearch(_ text: String) {
        let visibleSessions = sessionManager.visibleSessions

        if text.isEmpty {
            for session in visibleSessions {
                session.terminalView.clearSearch()
                session.searchText = ""
                session.currentMatchIndex = 0
            }
            findBar.updateCounter(current: 0, total: 0)
            return
        }

        // Search all visible sessions and aggregate results
        var globalTotal = 0
        var globalCurrent = 0

        for session in visibleSessions {
            session.searchText = text
            let found = session.terminalView.findNext(text, scrollToResult: false)
            let total = countMatches(text, in: session)
            if found && total > 0 {
                session.currentMatchIndex = min(session.currentMatchIndex + 1, total)
                if session.currentMatchIndex == 0 { session.currentMatchIndex = 1 }
            } else {
                session.currentMatchIndex = 0
            }
            globalTotal += total
            globalCurrent += session.currentMatchIndex
        }

        // Scroll to result in the focused session
        if let focused = sessionManager.activeSession {
            _ = focused.terminalView.findNext(text, scrollToResult: true)
        }

        findBar.updateCounter(current: max(globalCurrent, globalTotal > 0 ? 1 : 0), total: globalTotal)
    }

    /// Counts all occurrences of the search term in the terminal buffer.
    private func countMatches(_ text: String, in session: TerminalSession) -> Int {
        let terminal = session.terminalView.getTerminal()

        // Extract all buffer text using a large row bound — getText clamps internally.
        let start = Position(col: 0, row: 0)
        let end = Position(col: terminal.cols - 1, row: 100_000)
        let allText = terminal.getText(start: start, end: end)
        guard !allText.isEmpty else { return 0 }

        let searchTerm = text.lowercased()
        let haystack = allText.lowercased()

        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: searchTerm, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    // MARK: - Link Detection & Handling

    /// Installs event monitors for click-to-open links and hover cursor changes,
    /// plus a periodic scan that keeps persistent underlines on all detected links.
    /// OSC 8 explicit hyperlinks are handled by SwiftTerm's built-in mouseUp handler.
    private func installLinkMonitors() {
        // Track mouseDown position to distinguish clicks from drag-selections.
        linkMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            self.trackMouseDown(event)
            return event // Always pass through — terminal needs mouseDown for selection
        }

        // Click-to-open: intercept mouseUp to detect and open auto-detected links.
        // Only fires if mouseUp is at the same grid position as mouseDown (not a drag).
        // Cmd+click also works. If no match, passes through for OSC 8 handling.
        linkClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            if self.handleLinkClick(event) {
                return nil // Consume event — we handled a regex-detected link
            }
            return event // Pass through — SwiftTerm handles OSC 8 clicks
        }

        // Hover: change cursor to pointing hand when hovering over a detected link
        linkHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self else { return event }
            self.handleLinkHover(event)
            return event
        }

        // Periodic scan of visible rows to keep persistent underlines and gutters up to date.
        // Runs at 10 Hz so stale underlines from terminal redraws (e.g., Claude Code streaming)
        // are corrected within ~100ms. Scanning ~30 lines of regex is negligible overhead.
        linkScanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanVisibleLinks()
                self?.refreshGutters()
            }
        }
    }

    // MARK: - Persistent Link Underlines

    /// Scans all visible terminal panes for links and updates overlays with underlines.
    /// Called periodically by the link scan timer so underlines stay current as output scrolls.
    private func scanVisibleLinks() {
        for session in sessionManager.visibleSessions {
            scanLinks(for: session)
        }
    }

    /// Scans a single session's visible rows for links and updates its overlay.
    private func scanLinks(for session: TerminalSession) {
        let terminalView = session.terminalView
        let terminal = terminalView.getTerminal()
        let bounds = terminalView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let cell = cellDimensions(for: terminalView)
        var rects: [NSRect] = []

        for screenRow in 0..<terminal.rows {
            let bufferRow = screenRow + terminal.buffer.yDisp
            let lineStart = Position(col: 0, row: bufferRow)
            let lineEnd = Position(col: terminal.cols - 1, row: bufferRow)
            let lineText = terminal.getText(start: lineStart, end: lineEnd)
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)

            guard !lineText.isEmpty else { continue }

            let links = TerminalLinkDetector.detectAll(in: lineText, cwd: session.currentDirectory)

            for link in links {
                guard let colRange = TerminalLinkDetector.columnRange(for: link, in: lineText) else {
                    continue
                }
                let x = CGFloat(colRange.start) * cell.width
                let y = bounds.height - CGFloat(screenRow + 1) * cell.height + 1
                let width = CGFloat(colRange.length) * cell.width
                rects.append(NSRect(x: x, y: y, width: width, height: 1.0))
            }
        }

        let overlay = ensureLinkOverlay(for: session)
        overlay.updateUnderlines(rects)
    }

    // MARK: - Cell Dimension Computation

    /// Computes terminal cell dimensions from font metrics, matching SwiftTerm's internal
    /// `computeFontDimensions()`. Using `bounds / cols` gives incorrect values because
    /// SwiftTerm subtracts scroller width and floors the division, leaving leftover pixels.
    private func cellDimensions(
        for terminalView: LocalProcessTerminalView
    ) -> (width: CGFloat, height: CGFloat) {
        let font = terminalView.font as CTFont
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let cellHeight = ceil(ascent + descent + leading)

        let nsFont = terminalView.font
        let glyph = nsFont.glyph(withName: "W")
        let cellWidth = nsFont.advancement(forGlyph: glyph).width

        return (width: max(1, cellWidth), height: max(1, cellHeight))
    }

    // MARK: - Grid Position Computation

    /// Computes the terminal grid position from a mouse event inside the terminal view.
    /// Returns (screenRow, screenCol) where screenRow is 0-based from the top of the visible area.
    /// Uses font-metric-based cell dimensions to match SwiftTerm's internal grid exactly.
    private func gridPosition(
        in terminalView: LocalProcessTerminalView,
        event: NSEvent
    ) -> (screenRow: Int, screenCol: Int)? {
        let point = terminalView.convert(event.locationInWindow, from: nil)
        guard terminalView.bounds.contains(point) else { return nil }

        let terminal = terminalView.getTerminal()
        let cell = cellDimensions(for: terminalView)

        // Terminal rows are top-down; NSView Y is bottom-up.
        let col = min(max(0, Int(point.x / cell.width)), terminal.cols - 1)
        let row = min(max(0, Int((terminalView.bounds.height - point.y) / cell.height)), terminal.rows - 1)
        return (screenRow: row, screenCol: col)
    }

    // MARK: - Click-to-Open Link Handling

    /// Records the grid position of a mouseDown so we can distinguish clicks from drags.
    private func trackMouseDown(_ event: NSEvent) {
        guard let window = view.window, event.window === window else {
            mouseDownGridPosition = nil
            return
        }

        for session in sessionManager.visibleSessions {
            if let grid = gridPosition(in: session.terminalView, event: event) {
                mouseDownGridPosition = (session: session.id, row: grid.screenRow, col: grid.screenCol)
                return
            }
        }
        mouseDownGridPosition = nil
    }

    /// Handles click-to-open on any visible terminal pane — detects URLs and file paths via regex.
    /// Only opens a link if mouseUp is at the same grid position as mouseDown (not a drag/selection).
    /// Cmd+click always works. Plain click works on detected links only.
    /// Returns true if a link was found and handled (event should be consumed).
    private func handleLinkClick(_ event: NSEvent) -> Bool {
        guard let window = view.window, event.window === window else { return false }

        let hasCmd = event.modifierFlags.contains(.command)

        // Hit-test against all visible sessions
        for session in sessionManager.visibleSessions {
            let terminalView = session.terminalView
            guard let grid = gridPosition(in: terminalView, event: event) else { continue }

            // For plain clicks (no Cmd), only open if mouseDown was at the same position.
            // This prevents drag-to-select from accidentally triggering link opens.
            if !hasCmd {
                guard let down = mouseDownGridPosition,
                      down.session == session.id,
                      down.row == grid.screenRow,
                      down.col == grid.screenCol else { continue }
            }

            let terminal = terminalView.getTerminal()
            if let link = detectLink(
                screenRow: grid.screenRow,
                screenCol: grid.screenCol,
                terminal: terminal,
                session: session
            ) {
                openDetectedLink(link)
                mouseDownGridPosition = nil
                return true
            }
        }

        mouseDownGridPosition = nil
        return false
    }

    /// Opens a detected link — URLs in browser, file paths in file pane, hashes to clipboard.
    private func openDetectedLink(_ link: DetectedLink) {
        switch link {
        case .url(let urlString, _):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .filePath(let path, let line, let col, _):
            handleFilePathClick(path: path, line: line, col: col)
        case .gitHash(let hash, _):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hash, forType: .string)
        }
    }

    // MARK: - Link Detection (Regex)

    /// Detects a URL or file path at the given screen position using regex.
    /// Converts screen row to buffer row using the public `buffer.yDisp` offset,
    /// then reads the line text via `terminal.getText()`.
    private func detectLink(
        screenRow: Int,
        screenCol: Int,
        terminal: Terminal,
        session: TerminalSession
    ) -> DetectedLink? {
        // Convert screen row to buffer row (screen is offset by scroll position)
        let bufferRow = screenRow + terminal.buffer.yDisp

        let lineStart = Position(col: 0, row: bufferRow)
        let lineEnd = Position(col: terminal.cols - 1, row: bufferRow)
        let lineText = terminal.getText(start: lineStart, end: lineEnd)

        // Only strip trailing spaces (terminal row padding). Leading spaces must
        // be preserved to maintain 1:1 grid-column-to-character-index alignment.
        let trimmed = lineText.replacingOccurrences(
            of: "\\s+$", with: "", options: .regularExpression
        )

        guard !trimmed.isEmpty else { return nil }

        return TerminalLinkDetector.detect(
            in: trimmed,
            at: screenCol,
            cwd: session.currentDirectory
        )
    }

    /// Routes a file/folder path click to the file explorer's top pane.
    /// Walks the parent chain to find RootSplitViewController.
    /// Folders: navigates into the directory. Files: selects the file and triggers preview.
    func handleFilePathClick(path: String, line: Int?, col: Int?) {
        let fileURL = URL(fileURLWithPath: path)

        // Walk parent chain to find RootSplitViewController
        var current: NSViewController? = parent
        while let vc = current {
            if let root = vc as? RootSplitViewController {
                let topPane = root.explorerContainer?.topPane
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    topPane?.openFolder(at: fileURL)
                } else {
                    topPane?.openFile(at: fileURL)
                }
                return
            }
            current = vc.parent
        }
    }

    // MARK: - Link Hover (Cmd+mouseMoved)

    /// Changes cursor to pointing hand when hovering over a detected link.
    /// Only affects cursor when the mouse is inside a terminal view.
    private func handleLinkHover(_ event: NSEvent) {
        guard let window = view.window, event.window === window else { return }

        // Only manage cursor when mouse is inside a terminal pane
        var insideTerminal = false

        for session in sessionManager.visibleSessions {
            let terminalView = session.terminalView
            let point = terminalView.convert(event.locationInWindow, from: nil)
            guard terminalView.bounds.contains(point) else { continue }

            insideTerminal = true

            if let grid = gridPosition(in: terminalView, event: event) {
                let terminal = terminalView.getTerminal()
                if detectLink(
                    screenRow: grid.screenRow,
                    screenCol: grid.screenCol,
                    terminal: terminal,
                    session: session
                ) != nil {
                    NSCursor.pointingHand.set()
                    return
                }
            }
        }

        // Only set I-beam when mouse is inside a terminal view
        if insideTerminal {
            NSCursor.iBeam.set()
        }
    }

    /// Returns or creates the link overlay for a specific session.
    /// Each visible session has its own overlay keyed by session ID.
    private func ensureLinkOverlay(for session: TerminalSession) -> TerminalLinkOverlayView {
        let terminalView = session.terminalView

        if let existing = linkOverlays[session.id] {
            // Move overlay to correct terminal view if needed
            if existing.superview !== terminalView {
                existing.removeFromSuperview()
                existing.frame = terminalView.bounds
                terminalView.addSubview(existing)
            }
            return existing
        }

        let overlay = TerminalLinkOverlayView(frame: terminalView.bounds)
        overlay.autoresizingMask = [.width, .height]
        terminalView.addSubview(overlay)
        linkOverlays[session.id] = overlay
        return overlay
    }

    // MARK: - Gutter Refresh

    /// Updates all visible gutter views with current cell height and triggers redraw.
    /// Called periodically by the link scan timer and after mark changes.
    private func refreshGutters() {
        for session in sessionManager.visibleSessions {
            guard let gutter = gutterViews[session.id] else { continue }

            // Compute cell height from the terminal view's frame and row count.
            let terminal = session.terminalView.getTerminal()
            let rows = terminal.rows
            if rows > 0 {
                gutter.cellHeight = session.terminalView.bounds.height / CGFloat(rows)
            }
            gutter.refreshGutter()
        }
    }

    // MARK: - Prompt Navigation (OSC 133)

    /// Installs a keyDown monitor to intercept Cmd+Up/Down for jumping between
    /// shell prompts using OSC 133 marks stored on the active session.
    private func installPromptNavMonitor() {
        promptNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option) else { return event }

            switch event.keyCode {
            case 126: // Up arrow
                if self.navigateToPrompt(direction: .up) { return nil }
            case 125: // Down arrow
                if self.navigateToPrompt(direction: .down) { return nil }
            default:
                break
            }
            return event
        }
    }

    private enum PromptDirection { case up, down }

    /// Scrolls the focused terminal to the nearest prompt mark in the given direction.
    /// Returns true if navigation occurred (event should be consumed).
    private func navigateToPrompt(direction: PromptDirection) -> Bool {
        guard let session = sessionManager.activeSession else { return false }
        let terminalView = session.terminalView

        // Only navigate if the event targets our terminal view's window.
        guard terminalView.window != nil,
              terminalView.window === view.window else { return false }

        let terminal = terminalView.getTerminal()
        let yDisp = terminal.buffer.yDisp

        // Use the viewport top (yDisp) as the reference for both directions.
        // This navigates to prompts that are off-screen — prompts already
        // visible in the viewport don't need navigation.
        let targetMark: CommandMark?
        switch direction {
        case .up:
            targetMark = session.promptMarkAbove(line: yDisp)
        case .down:
            targetMark = session.promptMarkBelow(line: yDisp)
        }

        guard let mark = targetMark else {
            // No mark found — for down, snap to the bottom of scrollback.
            if direction == .down {
                terminalView.scroll(toPosition: 1.0)
                return true
            }
            return false
        }

        // Scroll so the mark's line is at the top of the viewport.
        // Use scrollUp/scrollDown which handle clamping internally.
        let delta = yDisp - mark.absoluteLine
        if delta > 0 {
            terminalView.scrollUp(lines: delta)
        } else if delta < 0 {
            terminalView.scrollDown(lines: -delta)
        }
        return true
    }

    // MARK: - Hints Mode (Cmd+Shift+E)

    /// Installs a keyDown monitor for Cmd+Shift+E to activate hints/quick-select mode.
    private func installHintsHotkeyMonitor() {
        hintsHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            // Cmd+Shift+E activates hints mode
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            guard event.modifierFlags.contains(requiredFlags),
                  event.charactersIgnoringModifiers?.lowercased() == "e",
                  !self.hintsController.isActive else { return event }

            // Only activate if the event targets our window
            guard event.window === self.view.window else { return event }

            self.hintsController.activate(
                sessions: self.sessionManager.visibleSessions,
                cellDimensions: self.cellDimensions
            )
            return nil // Consume the hotkey event
        }
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Terminal resized — no action needed, SwiftTerm handles PTY resize
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Ignore terminal escape sequence title changes — we always show the directory name.
        // Tools like Claude Code set the terminal title, which would overwrite our tab name.
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Update tab title and store CWD on the session when the shell reports via OSC 7.
        // The stored CWD is used to resolve relative paths for click-to-open link detection.
        // OSC 7 sends a file:// URL (e.g. "file:///Users/foo/bar"), not a raw path.
        // We must extract the filesystem path so resolvePath() can use it correctly.
        Task { @MainActor [weak self] in
            guard let self, let directory else { return }

            // Parse file:// URL to extract the filesystem path; fall back to raw string.
            let path: String
            if directory.hasPrefix("file://"), let url = URL(string: directory) {
                path = url.path
            } else {
                path = directory
            }

            if let index = sessionManager.sessions.firstIndex(where: { $0.terminalView === source }) {
                sessionManager.sessions[index].currentDirectory = path
                // Only update the tab title if no custom name is set
                if sessionManager.sessions[index].customTabTitle == nil {
                    let dirName = URL(fileURLWithPath: path).lastPathComponent
                    tabBar.updateTabTitle(dirName, at: index)
                }
            }
            // CWD changed — relative paths may resolve differently now
            self.scanVisibleLinks()
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Process exited — could auto-close tab or show message
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let index = sessionManager.sessions.firstIndex(where: { $0.terminalView === source }) {
                tabBar.updateTabTitle("(exited)", at: index)
            }
        }
    }
}

// MARK: - TerminalFindBarDelegate

extension TerminalContainerViewController: TerminalFindBarDelegate {

    func findBarSearchTextDidChange(_ text: String) {
        // Reset match index on all visible sessions when search text changes
        for session in sessionManager.visibleSessions {
            session.currentMatchIndex = 0
        }
        performSearch(text)
    }

    func findBarDidRequestNextMatch() {
        let text = findBar.searchText
        guard !text.isEmpty else { return }

        let orderedSessions = sessionManager.visibleSessions
        guard !orderedSessions.isEmpty else { return }

        // Navigate across all visible panes in visual order.
        // Try next match in focused session first; if exhausted, move to next pane.
        let focusedSession = sessionManager.activeSession
        var globalTotal = 0
        var globalCurrent = 0

        // Find the focused session's position in the ordered list
        let focusedListIndex = orderedSessions.firstIndex(where: { $0.id == focusedSession?.id }) ?? 0

        // Try to advance in the focused session
        if let session = focusedSession {
            let total = countMatches(text, in: session)
            let found = session.terminalView.findNext(text, scrollToResult: true)
            if found && total > 0 {
                session.currentMatchIndex += 1
                if session.currentMatchIndex > total {
                    // Exhausted this pane — wrap to next pane
                    session.currentMatchIndex = total
                    let nextIdx = (focusedListIndex + 1) % orderedSessions.count
                    if nextIdx != focusedListIndex {
                        let nextSession = orderedSessions[nextIdx]
                        nextSession.currentMatchIndex = 0
                        _ = nextSession.terminalView.findNext(text, scrollToResult: true)
                        nextSession.currentMatchIndex = 1
                        // Focus the next pane visually but keep keyboard in find bar
                        if let sessionIdx = sessionManager.sessions.firstIndex(where: {
                            $0.id == nextSession.id
                        }) {
                            sessionManager.setFocused(index: sessionIdx)
                            applyFocusAppearance()
                            findBar.focus()
                        }
                    } else {
                        session.currentMatchIndex = 1
                    }
                }
            }
        }

        // Aggregate counts for the counter
        for session in orderedSessions {
            globalTotal += countMatches(text, in: session)
            globalCurrent += session.currentMatchIndex
        }
        findBar.updateCounter(current: globalCurrent, total: globalTotal)
    }

    func findBarDidRequestPreviousMatch() {
        let text = findBar.searchText
        guard !text.isEmpty else { return }

        let orderedSessions = sessionManager.visibleSessions
        guard !orderedSessions.isEmpty else { return }

        let focusedSession = sessionManager.activeSession
        var globalTotal = 0
        var globalCurrent = 0

        let focusedListIndex = orderedSessions.firstIndex(where: { $0.id == focusedSession?.id }) ?? 0

        if let session = focusedSession {
            let total = countMatches(text, in: session)
            let found = session.terminalView.findPrevious(text, scrollToResult: true)
            if found && total > 0 {
                session.currentMatchIndex -= 1
                if session.currentMatchIndex < 1 {
                    // Exhausted this pane — wrap to previous pane
                    session.currentMatchIndex = 1
                    let prevIdx = (focusedListIndex - 1 + orderedSessions.count) % orderedSessions.count
                    if prevIdx != focusedListIndex {
                        let prevSession = orderedSessions[prevIdx]
                        let prevTotal = countMatches(text, in: prevSession)
                        prevSession.currentMatchIndex = prevTotal
                        _ = prevSession.terminalView.findPrevious(text, scrollToResult: true)
                        if let sessionIdx = sessionManager.sessions.firstIndex(where: {
                            $0.id == prevSession.id
                        }) {
                            sessionManager.setFocused(index: sessionIdx)
                            applyFocusAppearance()
                            findBar.focus()
                        }
                    } else {
                        session.currentMatchIndex = total
                    }
                }
            }
        }

        for session in orderedSessions {
            globalTotal += countMatches(text, in: session)
            globalCurrent += session.currentMatchIndex
        }
        findBar.updateCounter(current: globalCurrent, total: globalTotal)
    }

    func findBarDidRequestFocusTerminal() {
        guard let session = sessionManager.activeSession else { return }
        view.window?.makeFirstResponder(session.terminalView)
    }
}

// MARK: - TerminalHintsDelegate

extension TerminalContainerViewController: TerminalHintsDelegate {

    func hintsController(
        _ controller: TerminalHintsController,
        didSelect match: HintMatch,
        action: HintAction
    ) {
        let linkText = TerminalLinkDetector.text(for: match.link)

        switch action {
        case .copy:
            // Copy the matched text to system clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(linkText, forType: .string)

        case .insertAtCursor:
            // Insert the matched text at the active terminal's cursor position
            if let session = sessionManager.activeSession {
                session.terminalView.send(txt: linkText)
            }

        case .defaultAction:
            // Route based on link type — same as Cmd+click behavior
            openDetectedLink(match.link)
        }
    }

    func hintsControllerDidDismiss(_ controller: TerminalHintsController) {
        // Restore focus to the active terminal after hints mode exits
        if let session = sessionManager.activeSession {
            view.window?.makeFirstResponder(session.terminalView)
        }
    }

}
