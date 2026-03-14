// WorkspaceViewController.swift
// Top-level container that stacks the LayoutBarView above the RootSplitViewController.
// Wires layout bar selection to split view snap, and divider drags to bar highlight clearing.

import AppKit

@MainActor
final class WorkspaceViewController: NSViewController, LayoutBarDelegate {

    // MARK: - Properties

    private let configuration: LayoutConfiguration
    private let layoutBar: LayoutBarView
    private let rootSplitVC: RootSplitViewController

    /// Local key event monitor for layout hotkey activation.
    /// `nonisolated(unsafe)` allows cleanup in deinit (nonisolated in Swift 6).
    nonisolated(unsafe) private var hotkeyMonitor: Any?

    // MARK: - Init

    init(configuration: LayoutConfiguration) {
        self.configuration = configuration
        self.layoutBar = LayoutBarView(columnOrder: configuration.columnOrder)
        self.rootSplitVC = RootSplitViewController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        // Layout bar — fixed height strip at top
        layoutBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(layoutBar)

        // Root split view — fills remaining space
        addChild(rootSplitVC)
        rootSplitVC.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rootSplitVC.view)

        NSLayoutConstraint.activate([
            layoutBar.topAnchor.constraint(equalTo: container.topAnchor),
            layoutBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            layoutBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            layoutBar.heightAnchor.constraint(equalToConstant: LayoutBarView.barHeight),

            rootSplitVC.view.topAnchor.constraint(equalTo: layoutBar.bottomAnchor),
            rootSplitVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rootSplitVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rootSplitVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Wire layout bar delegate
        layoutBar.delegate = self

        // Wire manual resize detection to clear layout bar highlight
        rootSplitVC.onManualResize = { [weak self] in
            self?.layoutBar.clearSelection()
        }

        // Wire column order changes (panel swaps) to clear layout bar highlight
        rootSplitVC.onColumnOrderChanged = { [weak self] in
            self?.layoutBar.clearSelection()
        }

        // Start with "All Panels" highlighted
        layoutBar.highlightLayout(.allEqual)

        // Apply initial theme/font and start observing changes
        layoutBar.applyTheme()
        layoutBar.startObservingTheme()
        layoutBar.startObservingFont()

        // Install global hotkey monitor for layout shortcuts
        installHotkeyMonitor()
    }

    deinit {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Hook Event Routing

    /// Route a hook event to the correct terminal tab.
    /// Called by AppDelegate when a singlepane:// URL is received.
    func handleHookEvent(sessionID: UUID, color: NSColor?, spinning: Bool?) {
        let terminal = rootSplitVC.terminalContainer
        terminal?.highlightTab(sessionID: sessionID, color: color)

        if let spinning {
            if spinning {
                terminal?.startSpinner(sessionID: sessionID)
            } else {
                terminal?.stopSpinner(sessionID: sessionID)
            }
        }
    }

    /// Switch to the terminal tab for the given session UUID.
    /// Called by the notification click-through handler in AppDelegate.
    func selectTerminalTab(sessionID: UUID) {
        rootSplitVC.terminalContainer?.selectTab(sessionID: sessionID)
    }

    /// Returns the tab title for a terminal session, used for notification body text.
    func tabTitle(forSessionID sessionID: UUID) -> String? {
        rootSplitVC.terminalContainer?.tabTitle(forSessionID: sessionID)
    }

    // MARK: - File Navigation

    /// Opens a file in the editor by navigating the file explorer to select it.
    /// Used by layout bar actions (e.g., "How to Enable") to open config files.
    func openFileInEditor(_ url: URL) {
        rootSplitVC.explorerContainer?.topPane.openFile(at: url)
    }

    // MARK: - Custom Layout Capture

    /// Captures the current workspace state as a CustomLayout.
    private func captureCurrentLayout() -> CustomLayout {
        var innerSplitRatios: [PanelType: CGFloat] = [:]
        if let explorer = rootSplitVC.explorerContainer {
            innerSplitRatios[.explorer] = explorer.currentSplitRatio()
        }

        return CustomLayout(
            id: UUID(),
            columnOrder: rootSplitVC.currentColumnOrder,
            panelVisibility: rootSplitVC.currentPanelVisibility(),
            panelWidthRatios: rootSplitVC.currentPanelWidthRatios(),
            innerSplitRatios: innerSplitRatios,
            createdAt: Date()
        )
    }

    // MARK: - Layout Hotkey Monitor

    /// Installs a local key event monitor that intercepts layout hotkeys from anywhere in the app.
    private func installHotkeyMonitor() {
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }

            // Check if this key event matches any layout hotkey binding
            guard let layoutID = LayoutHotkeyManager.shared.layoutIdentifier(for: event) else {
                return event
            }

            // Try preset layouts first
            if let preset = SnapLayout(rawValue: layoutID) {
                self.layoutBar.selectLayout(preset)
                return nil // Consume the event
            }

            // Try custom layouts by UUID
            if let uuid = UUID(uuidString: layoutID),
               let custom = CustomLayoutManager.shared.customLayouts.first(where: { $0.id == uuid }) {
                self.layoutBar.selectCustomLayout(custom)
                return nil // Consume the event
            }

            return event
        }
    }

    // MARK: - LayoutBarDelegate

    func layoutBarDidSelectLayout(_ layout: SnapLayout) {
        rootSplitVC.applyLayout(layout)
    }

    func layoutBarDidSelectCustomLayout(_ layout: CustomLayout) {
        rootSplitVC.applyCustomLayout(layout)

        // Restore inner split ratios
        if let explorerRatio = layout.innerSplitRatios[.explorer],
           let explorer = rootSplitVC.explorerContainer {
            explorer.applySplitRatio(explorerRatio)
        }
    }

    func layoutBarDidRequestSaveCustomLayout() {
        let layout = captureCurrentLayout()
        if CustomLayoutManager.shared.save(layout: layout) {
            layoutBar.reloadCustomLayouts()
        }
    }

    func layoutBarDidRequestDeleteCustomLayout(at index: Int) {
        CustomLayoutManager.shared.delete(at: index)
        layoutBar.reloadCustomLayouts()
    }

    func layoutBarDidReorderColumns(_ newOrder: [PanelType]) {
        rootSplitVC.reorderColumns(to: newOrder)
    }
}
