// FilePanelViewController.swift
// Manages a single file explorer pane: breadcrumb bar + file list (table or thumbnail grid).
// Bridges @Observable FilePanelViewModel to AppKit views via withObservationTracking.
// Supports view mode switching between list (NSTableView) and thumbnail (NSCollectionView).

import AppKit
import os.log
import UniformTypeIdentifiers

/// Diagnostic logger for the search UI pipeline (temporary — remove once search is stable).
private let searchLog = Logger(subsystem: "com.velocity.search", category: "ViewController")

extension Notification.Name {
    /// Posted after a drag-and-drop file operation completes.
    /// All file panels observe this to refresh their listings.
    static let fileOperationDidComplete = Notification.Name("fileOperationDidComplete")
}

/// Delegate protocol for notifying parent when a file is selected.
@MainActor
protocol FilePanelSelectionDelegate: AnyObject {
    func filePanelDidSelect(fileURL: URL?)
}

@MainActor
final class FilePanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Properties

    let viewModel: FilePanelViewModel
    weak var selectionDelegate: FilePanelSelectionDelegate?

    private let fileTableView = FileListTableView()
    private let scrollView = NSScrollView()
    private let thumbnailGridView = ThumbnailGridView()
    private let thumbnailScrollView = NSScrollView()
    private let breadcrumbBar = BreadcrumbBarView()

    /// Search results table — two-column layout (filename+path, excerpt).
    /// Visible only during deep search mode.
    private let searchTableView = NSTableView()
    private let searchScrollView = NSScrollView()

    /// "No results" label shown when a search completes with zero matches.
    private let noResultsLabel: NSTextField = {
        let label = NSTextField(labelWithString: "No results")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }()

    /// Row index currently in inline rename mode, or nil if not editing.
    private var editingRow: Int?

    /// Original URL of the file being renamed (for rename commit).
    private var editingFileURL: URL?

    // MARK: - Cached Rendering Resources

    /// Icon cache keyed by file extension to avoid repeated NSWorkspace.icon(forFile:) calls.
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    /// Pre-built folder SF Symbol image (avoids per-row SymbolConfiguration allocation).
    private static let folderImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(
            systemSymbolName: "folder.fill", accessibilityDescription: "Folder"
        )?.withSymbolConfiguration(config)
    }()

    /// Cached font for file list cells; updated when the active font changes.
    private var cachedListFont: NSFont = FontManager.shared.activeFont.withSize(12)

    /// Returns a cached file icon for the item, keyed by file extension.
    /// Falls back to NSWorkspace on cache miss and stores the result.
    private static func cachedIcon(for item: FileItem) -> NSImage {
        let ext = item.url.pathExtension.lowercased() as NSString
        if let cached = iconCache.object(forKey: ext) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        iconCache.setObject(icon, forKey: ext)
        return icon
    }

    // MARK: - Init

    init(viewModel: FilePanelViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        // Breadcrumb bar (replaces NSPathControl with ghost crumbs + dropdowns + edit mode)
        breadcrumbBar.delegate = self
        breadcrumbBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(breadcrumbBar)

        // Table view columns — all freely resizable with no max width cap.
        // Users can widen any column, pushing others off-screen (horizontal scroll).
        let nameCol = NSTableColumn(identifier: .fileName)
        nameCol.title = "Name"
        nameCol.width = 250
        nameCol.minWidth = 120
        nameCol.maxWidth = .greatestFiniteMagnitude
        nameCol.resizingMask = .userResizingMask

        let sizeCol = NSTableColumn(identifier: .fileSize)
        sizeCol.title = "Size"
        sizeCol.width = 80
        sizeCol.minWidth = 50
        sizeCol.maxWidth = .greatestFiniteMagnitude
        sizeCol.resizingMask = .userResizingMask

        let dateCol = NSTableColumn(identifier: .fileDateModified)
        dateCol.title = "Date Modified"
        dateCol.width = 140
        dateCol.minWidth = 80
        dateCol.maxWidth = .greatestFiniteMagnitude
        dateCol.resizingMask = .userResizingMask

        let kindCol = NSTableColumn(identifier: .fileKind)
        kindCol.title = "Kind"
        kindCol.width = 100
        kindCol.minWidth = 60
        kindCol.maxWidth = .greatestFiniteMagnitude
        kindCol.resizingMask = .userResizingMask

        // Sort descriptors for clickable column headers
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: false)
        kindCol.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)

        fileTableView.addTableColumn(nameCol)
        fileTableView.addTableColumn(sizeCol)
        fileTableView.addTableColumn(dateCol)
        fileTableView.addTableColumn(kindCol)

        fileTableView.dataSource = self
        fileTableView.delegate = self
        fileTableView.rowHeight = 22
        fileTableView.usesAlternatingRowBackgroundColors = true
        fileTableView.allowsMultipleSelection = true
        fileTableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        fileTableView.target = self

        // Disable auto-resizing so columns stay exactly where the user drags them.
        // Without this, NSTableView snaps columns to fill the visible width.
        fileTableView.columnAutoresizingStyle = .noColumnAutoresizing

        // Enable drag source and drop destination
        fileTableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        fileTableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        fileTableView.registerForDraggedTypes([.fileURL])

        // Scroll view wrapping the table (list view)
        scrollView.documentView = fileTableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        // Thumbnail grid collection view (hidden by default)
        setupThumbnailGrid()
        thumbnailScrollView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailScrollView.isHidden = true
        container.addSubview(thumbnailScrollView)

        // Search results table (hidden by default)
        setupSearchTable()
        searchScrollView.translatesAutoresizingMaskIntoConstraints = false
        searchScrollView.isHidden = true
        container.addSubview(searchScrollView)

        // "No results" label — centered over the search scroll view
        container.addSubview(noResultsLabel)

        // Layout — all scroll views share the same frame below the breadcrumb bar.
        // Only one is visible at a time based on the active view mode / search mode.
        NSLayoutConstraint.activate([
            breadcrumbBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            breadcrumbBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            breadcrumbBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: breadcrumbBar.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            thumbnailScrollView.topAnchor.constraint(equalTo: breadcrumbBar.bottomAnchor, constant: 4),
            thumbnailScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnailScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbnailScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            searchScrollView.topAnchor.constraint(equalTo: breadcrumbBar.bottomAnchor, constant: 4),
            searchScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            noResultsLabel.centerXAnchor.constraint(equalTo: searchScrollView.centerXAnchor),
            noResultsLabel.centerYAnchor.constraint(equalTo: searchScrollView.centerYAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        wireKeyboardHandlers()
        setupContextMenu()
        startObserving()

        // Initial load
        Task { await viewModel.loadDirectory() }

    }

    // MARK: - Find / Filter Focus

    /// Activates FAYT filter mode in the breadcrumb bar. Called by RootSplitVC on Cmd+F.
    func activateFilterMode() {
        breadcrumbBar.enterFilterMode()
    }

    // MARK: - Keyboard Handlers

    private func wireKeyboardHandlers() {
        fileTableView.onEnter = { [weak self] in self?.openSelectedItem() }
        fileTableView.onBackspace = { [weak self] in self?.viewModel.navigateUp() }
        fileTableView.onPaste = { [weak self] in self?.pasteFiles() }
        fileTableView.onFunctionKey = { keyNumber in
            NSLog("Function key F\(keyNumber) pressed — not yet implemented")
        }
        // FAYT: typing alphanumeric keys activates filter mode in the breadcrumb bar
        fileTableView.onTypingActivation = { [weak self] chars in
            self?.breadcrumbBar.enterFilterMode(initialText: chars)
        }
    }

    // MARK: - Observation

    /// Bridges @Observable changes to NSTableView reloads.
    /// Each property gets its own independent re-registration chain
    /// to avoid exponential observer growth.
    private func startObserving() {
        observeItems()
        observeDirectory()
        observeGhostState()
        observeTheme()
        observeFont()
        observeViewMode()
        observePendingNewFile()
        observeSearchMode()
        observeSearchResults()
        observeIsSearching()
        updateBreadcrumbs()
        applyViewMode()

        // Refresh this pane when any file operation completes (e.g. source pane after a move)
        NotificationCenter.default.addObserver(
            forName: .fileOperationDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel.loadDirectory()
            }
        }
    }

    /// Watches viewModel.items — re-registers only itself on change.
    /// Suppresses reloads while an inline rename is active to avoid destroying the editing cell.
    /// Reloads whichever view is currently active (table or thumbnail grid).
    private func observeItems() {
        withObservationTracking {
            _ = viewModel.items
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.editingRow == nil {
                    if self.viewModel.viewMode == .thumbnail {
                        self.thumbnailGridView.reloadData()
                    } else {
                        self.fileTableView.reloadData()
                    }
                }
                self.observeItems()
            }
        }
    }

    /// Watches viewModel.currentDirectory — re-registers only itself on change.
    private func observeDirectory() {
        withObservationTracking {
            _ = viewModel.currentDirectory
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateBreadcrumbs()
                self?.observeDirectory()
            }
        }
    }

    /// Watches viewModel.ghostPathComponents — re-registers only itself on change.
    private func observeGhostState() {
        withObservationTracking {
            _ = viewModel.ghostPathComponents
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateBreadcrumbs()
                self?.observeGhostState()
            }
        }
    }

    /// Watches ThemeManager for changes and re-applies file explorer colors.
    private func observeTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.observeTheme()
            }
        }
    }

    /// Watches FontManager for changes and re-applies font to file list cells.
    private func observeFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.observeFont()
            }
        }
    }

    /// Applies the active font and reloads the table to update cells.
    private func applyFont() {
        cachedListFont = FontManager.shared.activeFont.withSize(12)
        reloadVisibleRows()
    }

    /// Applies the active theme to file explorer backgrounds and text colors.
    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        scrollView.backgroundColor = theme.explorerBackground
        scrollView.drawsBackground = true
        fileTableView.backgroundColor = theme.explorerBackground
        thumbnailScrollView.backgroundColor = theme.explorerBackground
        thumbnailScrollView.drawsBackground = true
        thumbnailGridView.backgroundColors = [theme.explorerBackground]

        // Search results table
        searchScrollView.backgroundColor = theme.explorerBackground
        searchScrollView.drawsBackground = true
        searchTableView.backgroundColor = theme.explorerBackground
        noResultsLabel.textColor = theme.chromeTextSecondary

        breadcrumbBar.applyTheme()
        reloadVisibleRows()
        if viewModel.viewMode == .thumbnail {
            thumbnailGridView.reloadData()
        }
        if viewModel.isSearchMode {
            searchTableView.reloadData()
        }
    }

    // MARK: - Thumbnail Grid Setup

    /// Configures the thumbnail NSCollectionView with a flow layout.
    private func setupThumbnailGrid() {
        let layout = NSCollectionViewFlowLayout()
        let size = ViewModeStore.loadThumbnailSize().pointSize
        layout.itemSize = NSSize(width: size, height: size)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        thumbnailGridView.collectionViewLayout = layout
        thumbnailGridView.dataSource = self
        thumbnailGridView.delegate = self
        thumbnailGridView.isSelectable = true
        thumbnailGridView.allowsMultipleSelection = true
        thumbnailGridView.register(
            ThumbnailGridItem.self,
            forItemWithIdentifier: ThumbnailGridItem.identifier
        )

        // Enable drag source and drop destination
        thumbnailGridView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        thumbnailGridView.setDraggingSourceOperationMask(.copy, forLocal: false)
        thumbnailGridView.registerForDraggedTypes([.fileURL])

        thumbnailScrollView.documentView = thumbnailGridView
        thumbnailScrollView.hasVerticalScroller = true
        thumbnailScrollView.hasHorizontalScroller = false
        thumbnailScrollView.autohidesScrollers = true

        // Wire keyboard and mouse handlers (mirrors list view)
        thumbnailGridView.onEnter = { [weak self] in self?.openSelectedItem() }
        thumbnailGridView.onBackspace = { [weak self] in self?.viewModel.navigateUp() }
        thumbnailGridView.onPaste = { [weak self] in self?.pasteFiles() }
        // Double-click navigates into folders; files stay single-click ("Open" via context menu)
        thumbnailGridView.onDoubleClick = { [weak self] in
            guard let self else { return }
            guard let indexPath = self.thumbnailGridView.selectionIndexPaths.first else { return }
            let index = indexPath.item
            guard index >= 0, index < self.viewModel.items.count else { return }
            let item = self.viewModel.items[index]
            if item.isDirectory {
                self.viewModel.navigateTo(item.url)
            }
        }
        thumbnailGridView.onTypingActivation = { [weak self] chars in
            self?.breadcrumbBar.enterFilterMode(initialText: chars)
        }
    }

    // MARK: - Search Table Setup

    /// Configures the search results NSTableView with two columns.
    private func setupSearchTable() {
        let nameCol = NSTableColumn(identifier: .searchFileName)
        nameCol.title = "Name"
        nameCol.width = 300
        nameCol.minWidth = 150

        let excerptCol = NSTableColumn(identifier: .searchExcerpt)
        excerptCol.title = "Match"
        excerptCol.width = 300
        excerptCol.minWidth = 100

        searchTableView.addTableColumn(nameCol)
        searchTableView.addTableColumn(excerptCol)
        searchTableView.headerView = nil
        searchTableView.rowHeight = 32
        searchTableView.usesAlternatingRowBackgroundColors = true
        searchTableView.allowsMultipleSelection = false
        searchTableView.doubleAction = #selector(searchResultDoubleClicked(_:))
        searchTableView.target = self
        searchTableView.dataSource = self
        searchTableView.delegate = self

        searchScrollView.documentView = searchTableView
        searchScrollView.hasVerticalScroller = true
        searchScrollView.hasHorizontalScroller = false
        searchScrollView.autohidesScrollers = true
    }

    // MARK: - Search Mode Activation

    /// Activates deep search mode. Called by Cmd+F or search icon click.
    func activateSearchMode() {
        breadcrumbBar.enterSearchMode()
    }

    // MARK: - Search Observation

    /// Watches viewModel.isSearchMode — toggles between file list and search results display.
    private func observeSearchMode() {
        withObservationTracking {
            _ = viewModel.isSearchMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySearchMode()
                self?.observeSearchMode()
            }
        }
    }

    /// Watches viewModel.searchResults — reloads the search table when results stream in.
    /// Always re-registers regardless of search mode to keep the observation chain alive.
    private func observeSearchResults() {
        withObservationTracking {
            _ = viewModel.searchResults
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Always re-register first to keep the chain alive
                self.observeSearchResults()
                guard self.viewModel.isSearchMode else { return }
                let count = self.viewModel.searchResults.count
                searchLog.debug("[observeSearchResults] reloading table — \(count) results")
                self.searchTableView.reloadData()
                self.updateNoResultsState()
            }
        }
    }

    /// Watches viewModel.isSearching — drives the spinner in the breadcrumb bar.
    private func observeIsSearching() {
        withObservationTracking {
            _ = viewModel.isSearching
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.breadcrumbBar.updateSearchingState(self.viewModel.isSearching)
                self.updateNoResultsState()
                self.observeIsSearching()
            }
        }
    }

    /// Switches visibility between file list and search results table.
    private func applySearchMode() {
        if viewModel.isSearchMode {
            // Hide normal file views, show search results
            scrollView.isHidden = true
            thumbnailScrollView.isHidden = true
            searchScrollView.isHidden = false

            let theme = ThemeManager.shared.activeTheme
            searchScrollView.backgroundColor = theme.explorerBackground
            searchScrollView.drawsBackground = true
            searchTableView.backgroundColor = theme.explorerBackground
        } else {
            // Hide search results, restore normal file views
            searchScrollView.isHidden = true
            noResultsLabel.isHidden = true
            applyViewMode()
        }
    }

    /// Shows or hides the "No results" label based on current search state.
    /// Only shown after a search has actually completed with zero results.
    private func updateNoResultsState() {
        let shouldShow = viewModel.isSearchMode
            && viewModel.hasSearchCompleted
            && !viewModel.isSearching
            && viewModel.searchResults.isEmpty

        noResultsLabel.isHidden = !shouldShow

        // Theme the label
        let theme = ThemeManager.shared.activeTheme
        noResultsLabel.textColor = theme.chromeTextSecondary
    }

    // MARK: - Search Result Cell Rendering

    /// Builds a cell view for the search results table.
    /// Column 1 (searchFileName): icon + filename + path subtitle.
    /// Column 2 (searchExcerpt): matching content excerpt with highlighted match.
    private func searchResultCell(for tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn,
              row < viewModel.searchResults.count else {
            searchLog.debug("[searchResultCell] guard failed — column=\(tableColumn?.identifier.rawValue ?? "nil") row=\(row) count=\(self.viewModel.searchResults.count)")
            return nil
        }

        let result = viewModel.searchResults[row]
        let item = result.fileItem
        let theme = ThemeManager.shared.activeTheme
        let identifier = column.identifier
        searchLog.debug("[searchResultCell] row=\(row) col=\(identifier.rawValue) name='\(item.name)' path='\(item.path)'")

        switch identifier {
        case .searchFileName:
            let cellView = NSTableCellView()
            cellView.identifier = identifier

            // File icon
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            if item.isDirectory {
                imageView.image = Self.folderImage
                imageView.contentTintColor = theme.chromeAccent.withAlphaComponent(0.7)
            } else {
                imageView.image = Self.cachedIcon(for: item)
            }
            cellView.addSubview(imageView)

            // Filename label (primary) — no truncation, clips at column edge
            let nameLabel = NSTextField(labelWithString: item.name)
            nameLabel.font = cachedListFont
            nameLabel.textColor = item.isDirectory
                ? theme.chromeAccent.withAlphaComponent(0.7)
                : theme.explorerText
            nameLabel.lineBreakMode = .byClipping
            nameLabel.maximumNumberOfLines = 1
            nameLabel.cell?.isScrollable = false
            nameLabel.cell?.wraps = false
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(nameLabel)
            cellView.textField = nameLabel

            // Path subtitle (secondary, smaller)
            let parentPath = item.path.parentPathFast
            let pathLabel = NSTextField(labelWithString: parentPath)
            pathLabel.font = cachedListFont.withSize(10)
            pathLabel.textColor = theme.chromeTextSecondary
            pathLabel.lineBreakMode = .byTruncatingHead
            pathLabel.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(pathLabel)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                nameLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                nameLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                nameLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 2),

                pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                pathLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            ])

            return cellView

        case .searchExcerpt:
            let cellView = NSTableCellView()
            cellView.identifier = identifier

            let excerptText = result.matchExcerpt ?? ""
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(label)
            cellView.textField = label

            // Highlight match markers (>>> and <<<) with accent color
            let attributed = highlightExcerpt(excerptText, theme: theme)
            label.attributedStringValue = attributed

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            return cellView

        default:
            return nil
        }
    }

    /// Highlights match markers (>>> and <<<) in excerpt text with the accent color.
    private func highlightExcerpt(_ excerpt: String, theme: Theme) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.explorerText,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        ]

        let highlightAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.chromeAccent,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        ]

        let result = NSMutableAttributedString()
        var remaining = excerpt

        while let startRange = remaining.range(of: ">>>") {
            // Add text before the marker
            let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
            result.append(NSAttributedString(string: before, attributes: baseAttributes))

            remaining = String(remaining[startRange.upperBound...])

            // Find the closing marker
            if let endRange = remaining.range(of: "<<<") {
                let matched = String(remaining[remaining.startIndex..<endRange.lowerBound])
                result.append(NSAttributedString(string: matched, attributes: highlightAttributes))
                remaining = String(remaining[endRange.upperBound...])
            } else {
                // No closing marker — append rest as highlighted
                result.append(NSAttributedString(string: remaining, attributes: highlightAttributes))
                remaining = ""
            }
        }

        // Append any remaining text after last marker
        if !remaining.isEmpty {
            result.append(NSAttributedString(string: remaining, attributes: baseAttributes))
        }

        return result
    }

    // MARK: - Search Result Actions

    @objc private func searchResultDoubleClicked(_ sender: Any) {
        let row = searchTableView.selectedRow
        guard row >= 0, row < viewModel.searchResults.count else { return }

        let result = viewModel.searchResults[row]
        let targetURL = result.fileItem.url

        if result.fileItem.isDirectory {
            // Navigate into directory and exit search
            viewModel.exitSearchMode()
            viewModel.navigateTo(targetURL)
        } else {
            // Navigate to parent directory, select file, exit search
            let parentDir = targetURL.deletingLastPathComponent()
            viewModel.exitSearchMode()
            viewModel.navigateTo(parentDir)

            // After directory loads, select the target file
            Task { @MainActor in
                // Wait briefly for directory to load
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                self.selectFile(at: targetURL)
            }
        }
    }

    // MARK: - View Mode Switching

    /// Observes viewModel.viewMode changes and swaps between list/thumbnail display.
    private func observeViewMode() {
        withObservationTracking {
            _ = viewModel.viewMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyViewMode()
                self?.observeViewMode()
            }
        }
    }

    /// Switches visible scroll view based on the current view mode.
    /// Preserves selection state across the switch.
    private func applyViewMode() {
        let mode = viewModel.viewMode
        let thumbnailSize = ViewModeStore.loadThumbnailSize()

        breadcrumbBar.updateViewMode(mode, thumbnailSize: thumbnailSize)

        switch mode {
        case .list:
            thumbnailScrollView.isHidden = true
            scrollView.isHidden = false
            fileTableView.reloadData()
            // Restore selection in table
            if let selectedURL = viewModel.selectedFileURL,
               let row = viewModel.items.firstIndex(where: { $0.url == selectedURL }) {
                fileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            view.window?.makeFirstResponder(fileTableView)

        case .thumbnail:
            scrollView.isHidden = true
            thumbnailScrollView.isHidden = false
            updateThumbnailLayout()
            thumbnailGridView.reloadData()
            // Restore selection in grid
            if let selectedURL = viewModel.selectedFileURL,
               let index = viewModel.items.firstIndex(where: { $0.url == selectedURL }) {
                thumbnailGridView.selectionIndexes = IndexSet(integer: index)
            }
            view.window?.makeFirstResponder(thumbnailGridView)

        default:
            // Column, gallery, brief — not yet implemented. Fall back to list.
            thumbnailScrollView.isHidden = true
            scrollView.isHidden = false
        }
    }

    /// Updates the flow layout item size based on the global thumbnail size setting.
    private func updateThumbnailLayout() {
        guard let layout = thumbnailGridView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let size = ViewModeStore.loadThumbnailSize().pointSize
        layout.itemSize = NSSize(width: size, height: size)
        layout.invalidateLayout()
    }

    /// Reloads only the rows currently visible in the scroll viewport.
    /// Use instead of reloadData() when row count hasn't changed (e.g. theme/font updates).
    private func reloadVisibleRows() {
        let visible = fileTableView.rows(in: fileTableView.visibleRect)
        guard visible.length > 0 else { return }
        let rowRange = visible.location..<(visible.location + visible.length)
        let columnRange = 0..<fileTableView.numberOfColumns
        fileTableView.reloadData(
            forRowIndexes: IndexSet(integersIn: rowRange),
            columnIndexes: IndexSet(integersIn: columnRange)
        )
    }

    // MARK: - Breadcrumb Bar

    /// Updates the breadcrumb bar with the current directory and ghost state.
    /// Clears the filter pill since navigation resets filter state.
    private func updateBreadcrumbs() {
        breadcrumbBar.clearFilterPill()
        breadcrumbBar.update(
            url: viewModel.currentDirectory,
            ghostComponents: viewModel.ghostPathComponents,
            ghostBaseURL: viewModel.ghostBasePath
        )
    }

    // MARK: - Item Actions

    private func openSelectedItem() {
        let index: Int
        if viewModel.viewMode == .thumbnail {
            guard let first = thumbnailGridView.selectionIndexes.first else { return }
            index = first
        } else {
            let row = fileTableView.selectedRow
            guard row >= 0 else { return }
            index = row
        }
        guard index < viewModel.items.count else { return }
        let item = viewModel.items[index]

        if item.isDirectory {
            viewModel.navigateTo(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: Any) {
        let row = fileTableView.selectedRow
        guard row >= 0, row < viewModel.items.count else { return }
        let item = viewModel.items[row]
        // Double-click navigates into folders; files are opened via right-click "Open"
        if item.isDirectory {
            viewModel.navigateTo(item.url)
        }
    }

    @objc private func copyPathClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let path = viewModel.items[row].url.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)

        // Brief highlight flash on the filename to confirm the copy action
        flashFileNameHighlight(at: row)
    }

    @objc private func pasteToTerminalClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let path = viewModel.items[row].url.path
        let escaped = Self.shellEscape(path)

        // Walk the parent chain to find the terminal and send the escaped path
        var current: NSViewController? = parent
        while let vc = current {
            if let rootSplit = vc as? RootSplitViewController {
                rootSplit.terminalContainer?.sendToActiveSession(escaped)
                flashFileNameHighlight(at: row)
                return
            }
            current = vc.parent
        }
    }

    /// Shell-escapes a file path for safe insertion into a terminal session.
    private static func shellEscape(_ path: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/-_."))
        if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return path
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Flashes the filename text with the accent color for a split second to give visual
    /// feedback that the path was copied to the clipboard.
    private func flashFileNameHighlight(at row: Int) {
        guard let cellView = fileTableView.view(
            atColumn: 0, row: row, makeIfNecessary: false
        ) as? NSTableCellView,
              let textField = cellView.textField else { return }

        let theme = ThemeManager.shared.activeTheme
        let originalColor = textField.textColor ?? theme.explorerText

        // Flash to accent color, then restore
        textField.textColor = theme.chromeAccent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            textField.textColor = originalColor
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === searchTableView {
            return viewModel.searchResults.count
        }
        return viewModel.items.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else { return }
        viewModel.sort(by: key, ascending: descriptor.ascending)
        tableView.reloadData()
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Search results table — separate rendering path
        if tableView === searchTableView {
            return searchResultCell(for: tableColumn, row: row)
        }

        guard let column = tableColumn, row < viewModel.items.count else { return nil }
        let item = viewModel.items[row]
        let identifier = column.identifier

        let cellView: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = existing
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            cellView.textField = textField

            if identifier == .fileName {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                imageView.imageAlignment = .alignCenter
                cellView.addSubview(imageView)
                cellView.imageView = imageView

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
            }
        }

        // Apply theme text color and active font.
        // Folders use the accent color (matching layout icons) for visual distinction.
        // Hidden files (dotfiles) are dimmed to 50% opacity.
        let theme = ThemeManager.shared.activeTheme
        let hiddenAlpha: CGFloat = item.isHidden ? 0.5 : 1.0
        cellView.textField?.textColor = item.isDirectory
            ? theme.chromeAccent.withAlphaComponent(0.7 * hiddenAlpha)
            : theme.explorerText.withAlphaComponent(hiddenAlpha)
        cellView.textField?.font = cachedListFont

        switch identifier {
        case .fileName:
            cellView.textField?.stringValue = item.name
            cellView.imageView?.alphaValue = item.isHidden ? 0.5 : 1.0
            if item.isDirectory {
                cellView.imageView?.image = Self.folderImage
                cellView.imageView?.contentTintColor = theme.chromeAccent.withAlphaComponent(0.7)
            } else {
                cellView.imageView?.image = Self.cachedIcon(for: item)
                cellView.imageView?.contentTintColor = nil
            }
        case .fileSize:
            cellView.textField?.stringValue = item.isDirectory
                ? "--"
                : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        case .fileDateModified:
            cellView.textField?.stringValue = dateFormatter.string(from: item.dateModified)
        case .fileKind:
            cellView.textField?.stringValue = item.fileType?.localizedDescription ?? "Unknown"
        default:
            break
        }

        return cellView
    }

    /// Notify selection delegate when a file is selected.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }

        // Search results table — single-click selects for preview
        if tableView === searchTableView {
            let row = searchTableView.selectedRow
            if row >= 0, row < viewModel.searchResults.count {
                let result = viewModel.searchResults[row]
                viewModel.selectedFileURL = result.fileItem.url
                selectionDelegate?.filePanelDidSelect(fileURL: result.fileItem.url)
            }
            return
        }

        // Normal file list table
        let row = fileTableView.selectedRow
        if row >= 0, row < viewModel.items.count {
            let item = viewModel.items[row]
            viewModel.selectedFileURL = item.url
            selectionDelegate?.filePanelDidSelect(fileURL: item.url)
        } else {
            viewModel.selectedFileURL = nil
            selectionDelegate?.filePanelDidSelect(fileURL: nil)
        }
    }

    // MARK: - Drag Source

    /// Provide file URLs to the pasteboard when dragging begins.
    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        guard row < viewModel.items.count else { return nil }
        return viewModel.items[row].url as NSURL
    }

    // MARK: - Drop Destination

    /// Validate incoming file drops — accept file URLs into directory listings.
    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // Only accept file URL drops
        guard info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else {
            return []
        }

        // Retarget to "on" the whole table (drop into current directory)
        tableView.setDropRow(-1, dropOperation: .on)

        // Default to copy. Option key held = move.
        if NSEvent.modifierFlags.contains(.option),
           info.draggingSourceOperationMask.contains(.move) {
            return .move
        }
        return .copy
    }

    /// Handle the drop — copy or move files into the current directory.
    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }

        let destinationDir = viewModel.currentDirectory
        let isMove = NSEvent.modifierFlags.contains(.option)
            && info.draggingSourceOperationMask.contains(.move)

        Task {
            let fm = FileManager.default
            var errors: [String] = []

            // Build a set of existing names once — O(1) conflict checks instead of O(n) stat calls.
            var existingNames: Set<String>
            do {
                existingNames = Set(try fm.contentsOfDirectory(atPath: destinationDir.path))
            } catch {
                existingNames = []
            }

            for sourceURL in urls {
                var destName = sourceURL.lastPathComponent
                var destURL = destinationDir.appendingPathComponent(destName)

                // Skip dropping onto itself
                guard sourceURL != destURL else { continue }

                // Resolve name conflicts by checking the in-memory set
                if existingNames.contains(destName) {
                    let ext = sourceURL.pathExtension
                    let nameWithoutExt = (sourceURL.lastPathComponent as NSString).deletingPathExtension
                    var counter = 2
                    repeat {
                        destName = ext.isEmpty
                            ? "\(nameWithoutExt) \(counter)"
                            : "\(nameWithoutExt) \(counter).\(ext)"
                        counter += 1
                    } while existingNames.contains(destName)
                    destURL = destinationDir.appendingPathComponent(destName)
                }

                // Track the new name so subsequent files won't collide with it
                existingNames.insert(destName)

                do {
                    if isMove {
                        try fm.moveItem(at: sourceURL, to: destURL)
                    } else {
                        try fm.copyItem(at: sourceURL, to: destURL)
                    }
                } catch {
                    errors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Refresh this pane to show new files
            await viewModel.loadDirectory()

            // Notify other panes to refresh (source pane needs update after moves)
            NotificationCenter.default.post(name: .fileOperationDidComplete, object: nil)

            if !errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = "File Operation Failed"
                alert.informativeText = errors.joined(separator: "\n")
                alert.alertStyle = .warning
                alert.runModal()
            }
        }

        return true
    }

    // MARK: - Context Menu

    /// Installs a right-click context menu on the file list table view and thumbnail grid.
    private func setupContextMenu() {
        let tableMenu = NSMenu()
        tableMenu.font = FontManager.shared.activeFont.withSize(12)
        tableMenu.delegate = self
        fileTableView.menu = tableMenu

        let gridMenu = NSMenu()
        gridMenu.font = FontManager.shared.activeFont.withSize(12)
        gridMenu.delegate = self
        thumbnailGridView.menu = gridMenu
    }

    // MARK: - New File Menu

    /// Builds an NSMenu populated with a "New Folder" item, a separator,
    /// then file template items with their type icons.
    /// Used by both the breadcrumb `+` button and the right-click context menu.
    private func buildNewFileMenu() -> NSMenu {
        let menu = NSMenu(title: "New")
        menu.font = FontManager.shared.activeFont.withSize(12)

        // New Folder at the top
        let folderItem = NSMenuItem(
            title: "untitled",
            action: #selector(newFolderMenuItemSelected(_:)),
            keyEquivalent: ""
        )
        folderItem.target = self
        let folderIcon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
        folderItem.image = folderIcon
        folderItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(folderItem)

        menu.addItem(.separator())

        // File templates
        for (index, template) in FileTemplate.builtIn.enumerated() {
            let item = NSMenuItem(
                title: template.defaultFilename,
                action: #selector(newFileMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index

            // File-type icon from UTType
            if let utType = template.utType {
                item.image = NSWorkspace.shared.icon(for: utType)
                item.image?.size = NSSize(width: 16, height: 16)
            }

            menu.addItem(item)
        }
        return menu
    }

    /// Shows the new file type picker menu anchored below the given view.
    private func showNewFileMenu(anchoredTo view: NSView) {
        let menu = buildNewFileMenu()
        let point = NSPoint(x: 0, y: view.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func newFolderMenuItemSelected(_ sender: NSMenuItem) {
        Task { await viewModel.createNewFolder() }
    }

    @objc private func newFileMenuItemSelected(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < FileTemplate.builtIn.count else { return }
        let template = FileTemplate.builtIn[index]
        Task { await viewModel.createNewFile(template: template) }
    }

    // MARK: - Pending New File Observation

    /// Watches for a newly created file URL so we can select + begin inline rename.
    private func observePendingNewFile() {
        withObservationTracking {
            _ = viewModel.pendingNewFileURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handlePendingNewFile()
                self?.observePendingNewFile()
            }
        }
    }

    /// Selects the newly created file row and activates inline rename.
    private func handlePendingNewFile() {
        guard let fileURL = viewModel.pendingNewFileURL else { return }
        viewModel.pendingNewFileURL = nil

        // Find the row matching the new file URL
        guard let rowIndex = viewModel.items.firstIndex(where: { $0.url == fileURL }) else { return }

        // Reload table synchronously so the new row is available for cell access
        fileTableView.reloadData()

        // Select the row
        fileTableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        fileTableView.scrollRowToVisible(rowIndex)

        // Begin inline rename after layout pass completes so the cell view exists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.beginInlineRename(at: rowIndex, fileURL: fileURL)
        }
    }

    // MARK: - Programmatic File Selection

    /// Selects a file by URL, scrolls it into view, and notifies the selection delegate.
    /// Used by terminal link clicks to highlight a file in the pane and trigger preview.
    func selectFile(at fileURL: URL) {
        guard let rowIndex = viewModel.items.firstIndex(where: { $0.url == fileURL }) else { return }
        fileTableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        fileTableView.scrollRowToVisible(rowIndex)

        // Notify delegate so preview updates
        viewModel.selectedFileURL = fileURL
        selectionDelegate?.filePanelDidSelect(fileURL: fileURL)
    }

    // MARK: - Inline Rename

    /// Makes the name cell's text field editable and activates it for inline rename.
    private func beginInlineRename(at row: Int, fileURL: URL) {
        guard let cellView = fileTableView.view(
            atColumn: 0, row: row, makeIfNecessary: true
        ) as? NSTableCellView,
              let textField = cellView.textField else { return }

        editingRow = row
        editingFileURL = fileURL

        let isDir = fileURL.hasDirectoryPath
        // For files, strip extension so user edits just the stem.
        // For folders, edit the full name (folders have no extension).
        let editableName = isDir
            ? fileURL.lastPathComponent
            : (fileURL.lastPathComponent as NSString).deletingPathExtension
        textField.stringValue = editableName
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.delegate = self

        // Activate the field editor and select all text
        if window?.makeFirstResponder(textField) == true {
            textField.currentEditor()?.selectAll(nil)
        }
    }

    /// Commits or cancels inline rename when editing ends.
    private func endInlineRename(textField: NSTextField, cancelled: Bool) {
        guard editingRow != nil, let sourceURL = editingFileURL else { return }
        let ext = sourceURL.pathExtension
        let isDir = sourceURL.hasDirectoryPath

        // Restore cell to non-editable label state
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.delegate = nil
        editingRow = nil
        editingFileURL = nil

        // Reload table to pick up any updates suppressed during editing
        fileTableView.reloadData()

        if cancelled {
            // Restore the original filename display
            textField.stringValue = sourceURL.lastPathComponent
            return
        }

        let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)

        // For folders, use the typed name directly (no extension to append).
        // For files, re-attach the original extension to the stem.
        let newFilename: String
        if isDir {
            newFilename = newName.isEmpty ? sourceURL.lastPathComponent : newName
        } else {
            newFilename = newName.isEmpty
                ? sourceURL.lastPathComponent
                : (ext.isEmpty ? newName : "\(newName).\(ext)")
        }

        // If the name didn't change, nothing to do
        if newFilename == sourceURL.lastPathComponent {
            textField.stringValue = sourceURL.lastPathComponent
            return
        }

        Task { await viewModel.renameFile(from: sourceURL, to: newFilename) }
    }

    /// Convenience accessor for the view's window.
    private var window: NSWindow? { view.window }
}

// MARK: - BreadcrumbBarDelegate

extension FilePanelViewController: BreadcrumbBarDelegate {

    func breadcrumbBar(_ bar: BreadcrumbBarView, didNavigateTo url: URL) {
        viewModel.navigateTo(url)
    }

    func breadcrumbBar(
        _ bar: BreadcrumbBarView,
        requestSiblingsFor parentURL: URL,
        completion: @escaping ([String]) -> Void
    ) {
        Task {
            let siblings = await viewModel.fileService.subdirectories(of: parentURL)
            completion(siblings)
        }
    }

    func breadcrumbBarDidRequestNewFile(_ bar: BreadcrumbBarView, anchorView: NSView) {
        showNewFileMenu(anchoredTo: anchorView)
    }

    func breadcrumbBar(_ bar: BreadcrumbBarView, didChangeFilter filterText: String) {
        viewModel.filterText = filterText
        viewModel.applyFilter()
    }

    func breadcrumbBar(_ bar: BreadcrumbBarView, didConfirmFilter filterText: String) {
        // Filter is locked in — pill badge is shown by BreadcrumbBarView.
        // Return focus to the active file view so the user can navigate filtered results.
        let targetView: NSView = viewModel.viewMode == .thumbnail ? thumbnailGridView : fileTableView
        view.window?.makeFirstResponder(targetView)
    }

    func breadcrumbBarDidClearFilter(_ bar: BreadcrumbBarView) {
        viewModel.clearFilter()
        breadcrumbBar.clearFilterPill()
    }

    func breadcrumbBarDidRequestViewModeCycle(_ bar: BreadcrumbBarView) {
        viewModel.cycleViewMode()
    }

    func breadcrumbBarDidRequestThumbnailSizeCycle(_ bar: BreadcrumbBarView) {
        let current = ViewModeStore.loadThumbnailSize()
        let next = current.next
        ViewModeStore.save(thumbnailSize: next)
        updateThumbnailLayout()
        thumbnailGridView.reloadData()
        breadcrumbBar.updateViewMode(viewModel.viewMode, thumbnailSize: next)
    }

    func breadcrumbBarDidRequestTerminal(_ bar: BreadcrumbBarView) {
        let directory = viewModel.currentDirectory.path
        // Walk the parent chain to find RootSplitViewController → terminal container
        var current: NSViewController? = parent
        while let vc = current {
            if let rootSplit = vc as? RootSplitViewController {
                rootSplit.terminalContainer?.openNewSession(directory: directory)
                return
            }
            current = vc.parent
        }
    }

    func breadcrumbBarDidEnterSearchMode(_ bar: BreadcrumbBarView) {
        viewModel.enterSearchMode()
    }

    func breadcrumbBarDidExitSearchMode(_ bar: BreadcrumbBarView) {
        viewModel.exitSearchMode()
    }

    func breadcrumbBar(
        _ bar: BreadcrumbBarView,
        didChangeSearchQuery query: String,
        mode: SearchMode,
        options: SearchOptions
    ) {
        viewModel.performSearch(query: query, mode: mode, options: options)
    }
}

// MARK: - NSMenuDelegate (Context Menu)

extension FilePanelViewController: NSMenuDelegate {

    /// Populates the context menu dynamically based on the item under the cursor.
    /// Works for both list view (table) and thumbnail view (collection).
    /// Right-clicking an unselected item selects it first (standard macOS behavior).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Determine the clicked item index from whichever view is active
        let clickedRow: Int
        if viewModel.viewMode == .thumbnail {
            // Find collection view item under the mouse
            let locationInWindow = thumbnailGridView.window?.mouseLocationOutsideOfEventStream ?? .zero
            let locationInView = thumbnailGridView.convert(locationInWindow, from: nil)
            if let indexPath = thumbnailGridView.indexPathForItem(at: locationInView) {
                clickedRow = indexPath.item
            } else {
                clickedRow = -1
            }
        } else {
            clickedRow = fileTableView.clickedRow
        }

        // No item under cursor — show "New File" and "Paste" (if clipboard has files)
        guard clickedRow >= 0, clickedRow < viewModel.items.count else {
            let newFileItem = NSMenuItem(title: "New File", action: nil, keyEquivalent: "")
            newFileItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            newFileItem.image?.size = NSSize(width: 16, height: 16)
            newFileItem.submenu = buildNewFileMenu()
            menu.addItem(newFileItem)

            if pasteboardHasFiles() {
                let pasteItem = NSMenuItem(
                    title: "Paste",
                    action: #selector(pasteMenuItemClicked(_:)),
                    keyEquivalent: ""
                )
                pasteItem.target = self
                pasteItem.tag = -1
                pasteItem.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
                pasteItem.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(pasteItem)
            }
            return
        }

        // Select the clicked item if it isn't already selected
        if viewModel.viewMode == .thumbnail {
            if !thumbnailGridView.selectionIndexes.contains(clickedRow) {
                thumbnailGridView.selectionIndexes = IndexSet(integer: clickedRow)
            }
        } else {
            if !fileTableView.selectedRowIndexes.contains(clickedRow) {
                fileTableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
        }

        // Open in default application (files only)
        let item = viewModel.items[clickedRow]
        if !item.isDirectory {
            let openItem = NSMenuItem(
                title: "Open",
                action: #selector(openInDefaultAppMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            openItem.target = self
            openItem.tag = clickedRow
            openItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            openItem.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(openItem)
        }

        // Rename
        let renameItem = NSMenuItem(
            title: "Rename",
            action: #selector(renameMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.tag = clickedRow
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        renameItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(renameItem)

        // Copy Path
        let copyPathItem = NSMenuItem(
            title: "Copy Path",
            action: #selector(copyPathMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        copyPathItem.target = self
        copyPathItem.tag = clickedRow
        copyPathItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        copyPathItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(copyPathItem)

        // Send Path to Terminal
        let sendToTerminalItem = NSMenuItem(
            title: "Send Path to Terminal",
            action: #selector(sendPathToTerminalMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        sendToTerminalItem.target = self
        sendToTerminalItem.tag = clickedRow
        sendToTerminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        sendToTerminalItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(sendToTerminalItem)

        // Open in Terminal (folders only)
        if item.isDirectory {
            let openInTerminalItem = NSMenuItem(
                title: "Open in Terminal",
                action: #selector(openInTerminalMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            openInTerminalItem.target = self
            openInTerminalItem.tag = clickedRow
            openInTerminalItem.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)
            openInTerminalItem.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(openInTerminalItem)
        }

        menu.addItem(.separator())

        // Copy (file/folder to clipboard)
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(copyFileMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.tag = clickedRow
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(copyItem)

        // Paste (if clipboard has files)
        if pasteboardHasFiles() {
            let pasteItem = NSMenuItem(
                title: "Paste",
                action: #selector(pasteMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            pasteItem.target = self
            pasteItem.tag = clickedRow
            pasteItem.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
            pasteItem.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(pasteItem)
        }

        // Duplicate (files only)
        if !item.isDirectory {
            let duplicateItem = NSMenuItem(
                title: "Duplicate",
                action: #selector(duplicateMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            duplicateItem.target = self
            duplicateItem.tag = clickedRow
            duplicateItem.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
            duplicateItem.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(duplicateItem)
        }

        // Delete (Trash)
        let deleteItem = NSMenuItem(
            title: "Delete",
            action: #selector(deleteMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.tag = clickedRow
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(deleteItem)
    }

    // MARK: - Pasteboard Helpers

    /// Returns true if the system pasteboard contains file URLs.
    private func pasteboardHasFiles() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    /// Reads file URLs from the system pasteboard.
    private func fileURLsFromPasteboard() -> [URL] {
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return [] }
        return urls
    }

    /// Pastes files from the clipboard into the current directory.
    private func pasteFiles() {
        let urls = fileURLsFromPasteboard()
        guard !urls.isEmpty else { return }
        Task { await viewModel.pasteFiles(urls) }
    }

    // MARK: - Context Menu Actions

    @objc private func openInDefaultAppMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        NSWorkspace.shared.open(viewModel.items[row].url)
    }

    @objc private func pasteMenuItemClicked(_ sender: NSMenuItem) {
        pasteFiles()
    }

    @objc private func renameMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let fileURL = viewModel.items[row].url
        if viewModel.viewMode == .thumbnail {
            showRenameAlert(for: fileURL)
        } else {
            beginInlineRename(at: row, fileURL: fileURL)
        }
    }

    @objc private func copyFileMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let fileURL = viewModel.items[row].url
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileURL as NSURL])
        flashFileNameHighlight(at: row)
    }

    @objc private func copyPathMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let path = viewModel.items[row].url.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        flashFileNameHighlight(at: row)
    }

    @objc private func sendPathToTerminalMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let escaped = Self.shellEscape(viewModel.items[row].url.path)
        var current: NSViewController? = parent
        while let vc = current {
            if let rootSplit = vc as? RootSplitViewController {
                rootSplit.terminalContainer?.sendToActiveSession(escaped)
                flashFileNameHighlight(at: row)
                return
            }
            current = vc.parent
        }
    }

    @objc private func openInTerminalMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let path = viewModel.items[row].url.path
        var current: NSViewController? = parent
        while let vc = current {
            if let rootSplit = vc as? RootSplitViewController {
                rootSplit.terminalContainer?.openNewSession(directory: path)
                return
            }
            current = vc.parent
        }
    }

    @objc private func duplicateMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let fileURL = viewModel.items[row].url
        Task { await viewModel.duplicateFile(fileURL) }
    }

    @objc private func deleteMenuItemClicked(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < viewModel.items.count else { return }
        let fileURL = viewModel.items[row].url

        let alert = NSAlert()
        alert.messageText = "Move \"\(fileURL.lastPathComponent)\" to Trash?"
        alert.informativeText = "This item will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task {
                await self?.viewModel.trashFile(fileURL)
                // Clear preview if the trashed file was being displayed
                if self?.viewModel.selectedFileURL == nil
                    || self?.viewModel.selectedFileURL == fileURL {
                    self?.selectionDelegate?.filePanelDidSelect(fileURL: nil)
                }
            }
        }
    }
}

// MARK: - NSTextFieldDelegate (Inline Rename)

extension FilePanelViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }

        // Check if editing ended via Escape (cancel) vs Enter/tab/click-away (commit)
        let movementKey = obj.userInfo?["NSTextMovement"] as? Int
        let cancelled = (movementKey == NSTextMovement.cancel.rawValue)

        endInlineRename(textField: textField, cancelled: cancelled)
    }
}

// MARK: - NSCollectionViewDataSource (Thumbnail Grid)

extension FilePanelViewController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(
            withIdentifier: ThumbnailGridItem.identifier,
            for: indexPath
        )
        guard let thumbnailCell = cell as? ThumbnailGridItem,
              indexPath.item < viewModel.items.count else { return cell }

        let item = viewModel.items[indexPath.item]
        let size = ViewModeStore.loadThumbnailSize()
        thumbnailCell.configure(with: item, thumbnailSize: size)
        return thumbnailCell
    }
}

// MARK: - NSCollectionViewDelegate (Thumbnail Grid)

extension FilePanelViewController: NSCollectionViewDelegate {

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let indexPath = indexPaths.first,
              indexPath.item < viewModel.items.count else { return }
        let item = viewModel.items[indexPath.item]
        viewModel.selectedFileURL = item.url
        selectionDelegate?.filePanelDidSelect(fileURL: item.url)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
        if collectionView.selectionIndexes.isEmpty {
            viewModel.selectedFileURL = nil
            selectionDelegate?.filePanelDidSelect(fileURL: nil)
        }
    }

    // MARK: - Collection View Drag Source

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        guard indexPath.item < viewModel.items.count else { return nil }
        return viewModel.items[indexPath.item].url as NSURL
    }

    // MARK: - Collection View Drop Destination

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard draggingInfo.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }

        // Drop into the current directory (not between items)
        proposedDropOperation.pointee = .on

        if NSEvent.modifierFlags.contains(.option),
           draggingInfo.draggingSourceOperationMask.contains(.move) {
            return .move
        }
        return .copy
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: any NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }

        let destinationDir = viewModel.currentDirectory
        let isMove = NSEvent.modifierFlags.contains(.option)
            && draggingInfo.draggingSourceOperationMask.contains(.move)

        Task {
            let fm = FileManager.default
            var existingNames: Set<String>
            do {
                existingNames = Set(try fm.contentsOfDirectory(atPath: destinationDir.path))
            } catch {
                existingNames = []
            }

            for sourceURL in urls {
                var destName = sourceURL.lastPathComponent
                var destURL = destinationDir.appendingPathComponent(destName)
                guard sourceURL != destURL else { continue }

                if existingNames.contains(destName) {
                    let ext = sourceURL.pathExtension
                    let nameWithoutExt = (sourceURL.lastPathComponent as NSString).deletingPathExtension
                    var counter = 2
                    repeat {
                        destName = ext.isEmpty
                            ? "\(nameWithoutExt) \(counter)"
                            : "\(nameWithoutExt) \(counter).\(ext)"
                        counter += 1
                    } while existingNames.contains(destName)
                    destURL = destinationDir.appendingPathComponent(destName)
                }

                existingNames.insert(destName)

                do {
                    if isMove {
                        try fm.moveItem(at: sourceURL, to: destURL)
                    } else {
                        try fm.copyItem(at: sourceURL, to: destURL)
                    }
                } catch {
                    NSLog("Drop operation failed: \(error.localizedDescription)")
                }
            }

            await viewModel.loadDirectory()
            NotificationCenter.default.post(name: .fileOperationDidComplete, object: nil)
        }

        return true
    }
}

// MARK: - Thumbnail View Rename

extension FilePanelViewController {

    /// Shows a rename alert dialog for the thumbnail view (no inline rename).
    func showRenameAlert(for fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let isDir = fileURL.hasDirectoryPath
        let ext = fileURL.pathExtension
        textField.stringValue = isDir
            ? fileURL.lastPathComponent
            : (fileURL.lastPathComponent as NSString).deletingPathExtension
        alert.accessoryView = textField

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }

            let newFilename: String
            if isDir {
                newFilename = newName
            } else {
                newFilename = ext.isEmpty ? newName : "\(newName).\(ext)"
            }

            guard newFilename != fileURL.lastPathComponent else { return }
            Task { await self?.viewModel.renameFile(from: fileURL, to: newFilename) }
        }
    }
}
