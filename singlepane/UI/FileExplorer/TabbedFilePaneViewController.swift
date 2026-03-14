// TabbedFilePaneViewController.swift
// Container that adds tab support to a file explorer pane.
// Owns a TabBarView (horizontal, at top) and an array of FilePanelViewControllers.
// Each tab has its own independent directory, selection, and navigation state.
// Mirrors the TerminalContainerViewController tab pattern.

import AppKit

@MainActor
final class TabbedFilePaneViewController: NSViewController, TabBarDelegate {

    // MARK: - Properties

    private let tabBar = TabBarView()
    /// Content area below the tab bar — hosts the active FilePanelViewController's view.
    /// Exposed for focus dimming (RootSplitViewController dims content, not the tab row).
    let contentView = NSView()
    private let fileService: FileService
    private let initialDirectory: URL

    /// All file panels — one per tab.
    private var panels: [FilePanelViewController] = []

    /// Index of the currently visible tab.
    private(set) var activeIndex: Int = 0

    /// Delegate for forwarding file selection to the preview panel.
    /// Re-wired to the active tab's FilePanelViewController on every tab switch.
    weak var selectionDelegate: FilePanelSelectionDelegate? {
        didSet { activePanel?.selectionDelegate = selectionDelegate }
    }

    /// Controls whether switching tabs fires a preview update.
    /// When true, switching to a tab with a selectedFileURL updates the preview.
    /// When false, preview stays as-is until the user selects a file in the new tab.
    var restorePreviewOnTabSwitch: Bool = true

    // MARK: - Panel Shift

    /// Whether this pane shows panel shift arrows. Only the top explorer pane enables this.
    var showShiftArrows: Bool = false

    /// Shift arrow buttons for reordering the explorer panel relative to neighbors.
    private let shiftArrows = PanelShiftArrowView(panelType: .explorer)

    /// Delegate for panel swap requests. Set by RootSplitViewController.
    weak var shiftDelegate: PanelShiftDelegate? {
        didSet { shiftArrows.shiftDelegate = shiftDelegate }
    }

    /// The currently active file panel, if any.
    var activePanel: FilePanelViewController? {
        guard panels.indices.contains(activeIndex) else { return nil }
        return panels[activeIndex]
    }

    // MARK: - Init

    init(initialDirectory: URL, fileService: FileService) {
        self.initialDirectory = initialDirectory
        self.fileService = fileService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        // Tab bar at the top
        tabBar.orientation = .horizontal
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)

        // Shift arrows — trailing edge of tab bar row (hidden by default)
        shiftArrows.translatesAutoresizingMaskIntoConstraints = false
        shiftArrows.isHidden = !showShiftArrows
        container.addSubview(shiftArrows)

        // Content area below the tab bar — hosts the active FilePanelViewController's view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            // Shift arrows — trailing edge, centered on tab bar
            shiftArrows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            shiftArrows.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),

            contentView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create the first tab
        createNewTab(directory: initialDirectory)

        // Apply initial theme/font and start observing changes
        tabBar.applyTheme()
        tabBar.startObservingTheme()
        tabBar.startObservingFont()
    }

    // MARK: - Tab Creation

    /// Creates a new tab with a file panel at the given directory.
    private func createNewTab(directory: URL) {
        let viewModel = FilePanelViewModel(initialDirectory: directory, fileService: fileService)
        let panel = FilePanelViewController(viewModel: viewModel)

        panels.append(panel)
        addChild(panel)

        // Tab title = directory name
        let title = directory.lastPathComponent
        tabBar.addTab(title: title)

        // Observe directory changes to keep tab title in sync
        observeDirectory(for: panels.count - 1)
    }

    // MARK: - Tab Switching

    /// Switches the visible content to the panel at the given index.
    private func switchToPanel(at index: Int) {
        guard index >= 0, index < panels.count else { return }

        // Remove current panel's view
        if let current = activePanel {
            current.selectionDelegate = nil
            current.view.removeFromSuperview()
        }

        activeIndex = index

        // Add new panel's view using Auto Layout constraints
        // (frame-based autoresizing causes the breadcrumb scroll view
        // to lose its layout before the first proper layout pass)
        let panel = panels[index]
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(panel.view)
        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            panel.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            panel.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // Wire selection delegate to the active tab
        panel.selectionDelegate = selectionDelegate

        // Optionally restore preview to this tab's selected file
        if restorePreviewOnTabSwitch, let selectedURL = panel.viewModel.selectedFileURL {
            selectionDelegate?.filePanelDidSelect(fileURL: selectedURL)
        }
    }

    // MARK: - Directory Observation

    /// Watches a tab's viewModel.currentDirectory and updates the tab title.
    /// Each tab gets its own independent observation chain.
    private func observeDirectory(for index: Int) {
        guard index < panels.count else { return }
        let viewModel = panels[index].viewModel

        withObservationTracking {
            _ = viewModel.currentDirectory
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, index < self.panels.count,
                      self.panels[index].viewModel === viewModel else { return }
                let dirName = viewModel.currentDirectory.lastPathComponent
                self.tabBar.updateTabTitle(dirName, at: index)
                self.observeDirectory(for: index)
            }
        }
    }

    // MARK: - Open File/Folder (Terminal Link Integration)

    /// Navigates into a folder in this pane — reuses the active tab if already there,
    /// otherwise navigates the active tab to the target directory.
    func openFolder(at folderURL: URL) {
        if let current = activePanel {
            if current.viewModel.currentDirectory == folderURL { return }
            current.viewModel.navigateTo(folderURL)
        } else {
            createNewTab(directory: folderURL)
        }
    }

    /// Opens a file in this pane — reuses the active tab if already in the file's parent
    /// directory, otherwise creates a new tab. After navigation, selects the file
    /// and triggers preview via the selection delegate.
    func openFile(at fileURL: URL) {
        let parentDir = fileURL.deletingLastPathComponent()

        // Check if the active tab is already in the target directory
        if let current = activePanel, current.viewModel.currentDirectory == parentDir {
            // Already there — just select the file
            current.selectFile(at: fileURL)
            return
        }

        // Create a new tab at the parent directory
        createNewTab(directory: parentDir)

        // After the directory loads, select the target file.
        // Observe the new panel's items to know when loading is complete.
        let newIndex = panels.count - 1
        guard newIndex >= 0, newIndex < panels.count else { return }
        let panel = panels[newIndex]

        observeItemsForSelection(panel: panel, fileURL: fileURL)
    }

    /// Watches a panel's items until the target file appears, then selects it.
    /// Self-cancelling — fires once and does not re-register.
    private func observeItemsForSelection(panel: FilePanelViewController, fileURL: URL) {
        withObservationTracking {
            _ = panel.viewModel.items
        } onChange: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel else { return }
                // If the file is already in the list, select it
                if panel.viewModel.items.contains(where: { $0.url == fileURL }) {
                    panel.selectFile(at: fileURL)
                } else {
                    // Items may have loaded but file not yet present — retry once
                    self.observeItemsForSelection(panel: panel, fileURL: fileURL)
                }
            }
        }
    }

    // MARK: - Shift Arrow Update

    /// Updates shift arrow visibility and tooltips from computed state.
    /// Only effective when `showShiftArrows` is true (top explorer pane).
    func updateShiftArrows(_ state: ShiftArrowState) {
        guard showShiftArrows else { return }
        shiftArrows.isHidden = false
        shiftArrows.update(state)
    }

    // MARK: - TabBarDelegate

    func tabBarDidSelectTab(at index: Int) {
        switchToPanel(at: index)
    }

    func tabBarDidCloseTab(at index: Int) {
        guard panels.count > 1, index < panels.count else { return }

        let panel = panels.remove(at: index)
        panel.view.removeFromSuperview()
        panel.removeFromParent()

        // Adjust active index
        if activeIndex >= panels.count {
            activeIndex = max(0, panels.count - 1)
        }

        // Re-observe directories for shifted tabs
        for i in index..<panels.count {
            observeDirectory(for: i)
        }

        switchToPanel(at: activeIndex)
    }

    func tabBarDidRequestNewTab() {
        // New tab opens to the same directory as the current tab
        let directory = activePanel?.viewModel.currentDirectory ?? initialDirectory
        createNewTab(directory: directory)
    }
}
