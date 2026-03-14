// DualPaneExplorerViewController.swift
// Vertically stacked dual-pane file explorer using a nested NSSplitView.
// Each pane is a TabbedFilePaneViewController with independent tab support.
// Both panes default to ~/Documents. Divider between panes is draggable.

import AppKit

@MainActor
final class DualPaneExplorerViewController: NSSplitViewController {

    // MARK: - Properties

    private(set) var topPane: TabbedFilePaneViewController!
    private(set) var bottomPane: TabbedFilePaneViewController!

    /// Delegate for forwarding file selection to the preview panel.
    weak var selectionDelegate: FilePanelSelectionDelegate?

    // MARK: - Lifecycle

    override func loadView() {
        let themedSV = ThemedSplitView()
        themedSV.isVertical = false  // horizontal split (top/bottom panes stacked vertically)
        themedSV.wantsLayer = true
        splitView = themedSV
        super.loadView()
    }

    override func viewDidLoad() {
        // Default directory for both panes
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())

        // Shared file service across all tabs in both panes
        let fileService = FileService()

        // Top pane — shift arrows enabled (represents the whole explorer panel)
        topPane = TabbedFilePaneViewController(initialDirectory: documentsURL, fileService: fileService)
        topPane.showShiftArrows = true

        let topItem = NSSplitViewItem(viewController: topPane)
        topItem.minimumThickness = 150
        topItem.canCollapse = true
        addSplitViewItem(topItem)

        // Bottom pane
        bottomPane = TabbedFilePaneViewController(initialDirectory: documentsURL, fileService: fileService)

        let bottomItem = NSSplitViewItem(viewController: bottomPane)
        bottomItem.minimumThickness = 150
        bottomItem.canCollapse = true
        addSplitViewItem(bottomItem)

        super.viewDidLoad()
    }

    private var hasAppliedInitialProportions = false

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasAppliedInitialProportions {
            hasAppliedInitialProportions = true
            // Equal 50/50 split
            let midpoint = splitView.bounds.height / 2
            splitView.setPosition(midpoint, ofDividerAt: 0)
        }
    }

    // MARK: - Split Ratio (for custom layout capture/restore)

    /// Returns the top pane height as a ratio (0–1) of total split height.
    func currentSplitRatio() -> CGFloat {
        let totalHeight = splitView.bounds.height
        guard totalHeight > 0, splitViewItems.count == 2 else { return 0.5 }
        let topHeight = splitViewItems[0].viewController.view.frame.height
        return topHeight / totalHeight
    }

    /// Restores the top/bottom split position from a saved ratio.
    func applySplitRatio(_ ratio: CGFloat) {
        let totalHeight = splitView.bounds.height
        guard totalHeight > 0 else { return }
        let clampedRatio = max(0.1, min(0.9, ratio))
        splitView.setPosition(totalHeight * clampedRatio, ofDividerAt: 0)
    }

    // MARK: - Selection Delegate

    /// Wire the selection delegate to both tabbed panes after initialization.
    func wireSelectionDelegate(_ delegate: FilePanelSelectionDelegate) {
        self.selectionDelegate = delegate
        topPane.selectionDelegate = delegate
        bottomPane.selectionDelegate = delegate
    }
}
