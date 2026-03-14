// BreadcrumbBarView.swift
// Container view that lays out breadcrumb segments horizontally.
// Displays current path segments + ghost (faded) segments for previously visited deeper paths.
// Clicking empty space enters edit mode (path text field with autocomplete).

import AppKit

/// Actions emitted by the breadcrumb bar to its owner.
@MainActor
protocol BreadcrumbBarDelegate: AnyObject {
    /// User navigated to a path via breadcrumb click, ghost click, or dropdown selection.
    func breadcrumbBar(_ bar: BreadcrumbBarView, didNavigateTo url: URL)
    /// User requested sibling directories for a segment's dropdown menu.
    func breadcrumbBar(
        _ bar: BreadcrumbBarView,
        requestSiblingsFor parentURL: URL,
        completion: @escaping ([String]) -> Void
    )
    /// User clicked the "+" button to create a new file.
    func breadcrumbBarDidRequestNewFile(_ bar: BreadcrumbBarView, anchorView: NSView)
    /// User clicked the terminal button to open a terminal in the current directory.
    func breadcrumbBarDidRequestTerminal(_ bar: BreadcrumbBarView)
    /// FAYT: filter text changed in real-time.
    func breadcrumbBar(_ bar: BreadcrumbBarView, didChangeFilter filterText: String)
    /// FAYT: user pressed Enter to lock in the filter.
    func breadcrumbBar(_ bar: BreadcrumbBarView, didConfirmFilter filterText: String)
    /// FAYT: user dismissed the filter pill or pressed Escape — clear filter.
    func breadcrumbBarDidClearFilter(_ bar: BreadcrumbBarView)
    /// User clicked the view mode cycle button.
    func breadcrumbBarDidRequestViewModeCycle(_ bar: BreadcrumbBarView)
    /// User clicked the thumbnail size cycle button.
    func breadcrumbBarDidRequestThumbnailSizeCycle(_ bar: BreadcrumbBarView)
    /// User entered deep search mode (search icon or Cmd+F).
    func breadcrumbBarDidEnterSearchMode(_ bar: BreadcrumbBarView)
    /// User exited deep search mode (Escape or search icon toggle).
    func breadcrumbBarDidExitSearchMode(_ bar: BreadcrumbBarView)
    /// Search query or options changed while in search mode.
    func breadcrumbBar(
        _ bar: BreadcrumbBarView,
        didChangeSearchQuery query: String,
        mode: SearchMode,
        options: SearchOptions
    )
}

@MainActor
final class BreadcrumbBarView: NSView {

    // MARK: - Properties

    weak var delegate: BreadcrumbBarDelegate?

    /// The currently displayed directory path.
    private(set) var currentURL: URL?

    /// Ghost breadcrumb component names (faded trailing segments).
    private(set) var ghostComponents: [String] = []

    /// Base URL from which ghost components extend.
    private(set) var ghostBaseURL: URL?

    /// Whether the bar is currently in edit mode (showing a text field).
    private(set) var isEditMode = false

    /// Whether the bar is currently in deep search mode (search field + toggle icons).
    private(set) var isSearchMode = false

    /// Current deep search mode (filename vs content).
    private var searchMode: SearchMode = .filename

    /// Current deep search options (case sensitivity, regex).
    private var searchOptions = SearchOptions()

    // MARK: - Subviews

    /// Scroll wrapper — clips and horizontally scrolls the segment container.
    private let scrollView = NSScrollView()

    /// Document view inside the scroll view — holds breadcrumb segments.
    private let segmentContainer = NSView()

    private let actionStrip = NSStackView()
    private let viewModeButton = NSButton()
    private let thumbnailSizeButton = NSButton()
    private let terminalButton = NSButton()
    private let searchButton = NSButton()
    private let newFileButton = NSButton()
    private lazy var editField = BreadcrumbEditField()

    /// Deep search text field — overlays breadcrumbs during search mode.
    private let searchTextField = NSTextField()

    /// Search mode toggle buttons — visible only when search mode is active.
    private let searchModeToggle = NSButton()   // filename / content
    private let caseSensitiveToggle = NSButton() // Aa
    private let regexToggle = NSButton()         // .*

    /// Clear button — clears the search text field.
    private let searchClearButton = NSButton()

    /// Container for search toggle icons — shown only in search mode.
    private let searchToggleStrip = NSStackView()

    /// Indeterminate spinner shown left of search field while a search is running.
    private let searchSpinner = NSProgressIndicator()

    /// Static icon shown left of search field when search mode is active but idle.
    private let searchStatusIcon = NSImageView()

    /// Active filter pill badge, shown when a FAYT filter is locked in.
    private var filterPill: FilterPillView?

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

        // Scroll view — horizontal-only, no visible scrollbar.
        // Wraps the segment container so deep paths can be scrolled.
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Hide the horizontal scroller — scroll via trackpad/mouse wheel only.
        if let scroller = scrollView.horizontalScroller {
            scroller.scrollerStyle = .overlay
            scroller.alphaValue = 0
        }

        // Segment container — document view inside the scroll view.
        segmentContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = segmentContainer
        addSubview(scrollView)

        // Pin segmentContainer's height to the scroll view so it doesn't scroll vertically.
        // Width is unconstrained — determined by segment content (can exceed scroll view width).
        NSLayoutConstraint.activate([
            segmentContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            segmentContainer.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            segmentContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        ])

        // Action strip — trailing stack of icon buttons (extensible for FAYT, etc.)
        actionStrip.orientation = .horizontal
        actionStrip.spacing = 2
        actionStrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionStrip)

        // Thumbnail size cycle button — only visible in thumbnail view mode
        setupThumbnailSizeButton()
        actionStrip.addArrangedSubview(thumbnailSizeButton)
        thumbnailSizeButton.isHidden = true

        // View mode cycle button — toggles between list / thumbnail
        setupViewModeButton()
        actionStrip.addArrangedSubview(viewModeButton)

        // Terminal button — opens a terminal in the current directory
        setupTerminalButton()
        actionStrip.addArrangedSubview(terminalButton)

        // "+" button for new file creation
        setupNewFileButton()
        actionStrip.addArrangedSubview(newFileButton)

        // Search button — far right, toggles search mode on/off
        setupSearchButton()
        actionStrip.addArrangedSubview(searchButton)

        // Edit field — overlays everything during path edit mode
        editField.translatesAutoresizingMaskIntoConstraints = false
        editField.isHidden = true
        editField.editDelegate = self
        addSubview(editField)

        // Deep search mode UI
        setupSearchSpinner()
        setupSearchTextField()
        setupSearchToggleStrip()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: actionStrip.leadingAnchor, constant: -4
            ),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            actionStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionStrip.centerYAnchor.constraint(equalTo: centerYAnchor),

            editField.leadingAnchor.constraint(equalTo: leadingAnchor),
            editField.trailingAnchor.constraint(equalTo: trailingAnchor),
            editField.topAnchor.constraint(equalTo: topAnchor),
            editField.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    /// Configures the view mode cycle button. Defaults to list icon.
    private func setupViewModeButton() {
        viewModeButton.bezelStyle = .inline
        viewModeButton.isBordered = false
        viewModeButton.title = ""
        viewModeButton.image = NSImage(
            systemSymbolName: "list.bullet",
            accessibilityDescription: "Cycle view mode"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        viewModeButton.imagePosition = .imageOnly
        viewModeButton.target = self
        viewModeButton.action = #selector(viewModeButtonClicked(_:))
        viewModeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewModeButton.widthAnchor.constraint(equalToConstant: 22),
            viewModeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    /// Configures the thumbnail size cycle button. Hidden by default.
    private func setupThumbnailSizeButton() {
        thumbnailSizeButton.bezelStyle = .inline
        thumbnailSizeButton.isBordered = false
        thumbnailSizeButton.title = ""
        thumbnailSizeButton.image = NSImage(
            systemSymbolName: "m.circle",
            accessibilityDescription: "Cycle thumbnail size"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        thumbnailSizeButton.imagePosition = .imageOnly
        thumbnailSizeButton.target = self
        thumbnailSizeButton.action = #selector(thumbnailSizeButtonClicked(_:))
        thumbnailSizeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbnailSizeButton.widthAnchor.constraint(equalToConstant: 22),
            thumbnailSizeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    /// Configures the terminal button with a terminal SF Symbol.
    private func setupTerminalButton() {
        terminalButton.bezelStyle = .inline
        terminalButton.isBordered = false
        terminalButton.title = ""
        terminalButton.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "Open terminal here"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        terminalButton.imagePosition = .imageOnly
        terminalButton.target = self
        terminalButton.action = #selector(terminalButtonClicked(_:))
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalButton.widthAnchor.constraint(equalToConstant: 22),
            terminalButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    /// Configures the search button with a magnifying glass SF Symbol.
    private func setupSearchButton() {
        searchButton.bezelStyle = .inline
        searchButton.isBordered = false
        searchButton.title = ""
        searchButton.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Filter files"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        searchButton.imagePosition = .imageOnly
        searchButton.target = self
        searchButton.action = #selector(searchButtonClicked(_:))
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchButton.widthAnchor.constraint(equalToConstant: 22),
            searchButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    /// Configures the "+" button with an SF Symbol icon, matching breadcrumb styling.
    private func setupNewFileButton() {
        newFileButton.bezelStyle = .inline
        newFileButton.isBordered = false
        newFileButton.title = ""
        newFileButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New file"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        newFileButton.imagePosition = .imageOnly
        newFileButton.target = self
        newFileButton.action = #selector(newFileButtonClicked(_:))
        newFileButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newFileButton.widthAnchor.constraint(equalToConstant: 22),
            newFileButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Search Mode Setup

    /// Configures the search spinner and static icon — shown left of the search text field.
    private func setupSearchSpinner() {
        // Indeterminate spinner (small circular style)
        searchSpinner.style = .spinning
        searchSpinner.controlSize = .small
        searchSpinner.isIndeterminate = true
        searchSpinner.isDisplayedWhenStopped = false
        searchSpinner.isHidden = true
        searchSpinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchSpinner)

        // Static magnifying glass icon — shown when search mode is active but idle
        searchStatusIcon.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Search idle"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        searchStatusIcon.imageScaling = .scaleProportionallyDown
        searchStatusIcon.isHidden = true
        searchStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchStatusIcon)

        NSLayoutConstraint.activate([
            searchSpinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            searchSpinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchSpinner.widthAnchor.constraint(equalToConstant: 16),
            searchSpinner.heightAnchor.constraint(equalToConstant: 16),

            searchStatusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            searchStatusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchStatusIcon.widthAnchor.constraint(equalToConstant: 16),
            searchStatusIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    /// Configures the search text field — hidden by default, overlays breadcrumbs during search.
    /// The toggle strip sits inside the trailing edge of the text field area.
    private func setupSearchTextField() {
        searchTextField.placeholderString = "Search..."
        searchTextField.font = FontManager.shared.activeFont.withSize(12)
        searchTextField.isBezeled = true
        searchTextField.bezelStyle = .roundedBezel
        searchTextField.focusRingType = .none
        searchTextField.isHidden = true
        searchTextField.delegate = self
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchTextField)

        // Leading after spinner/icon, trailing before the action strip (search button)
        NSLayoutConstraint.activate([
            searchTextField.leadingAnchor.constraint(equalTo: searchSpinner.trailingAnchor, constant: 4),
            searchTextField.trailingAnchor.constraint(equalTo: actionStrip.leadingAnchor, constant: -4),
            searchTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Configures the search toggle strip — filename/content, case, regex toggles.
    /// Positioned inside the trailing edge of the search text field.
    private func setupSearchToggleStrip() {
        searchToggleStrip.orientation = .horizontal
        searchToggleStrip.spacing = 2
        searchToggleStrip.translatesAutoresizingMaskIntoConstraints = false
        searchToggleStrip.isHidden = true

        // Filename/Content toggle
        setupToggleButton(
            searchModeToggle,
            symbolName: "doc.text",
            accessibilityLabel: "Search filenames",
            action: #selector(searchModeToggleClicked(_:))
        )
        searchToggleStrip.addArrangedSubview(searchModeToggle)

        // Case Sensitive toggle
        setupToggleButton(
            caseSensitiveToggle,
            symbolName: "textformat",
            accessibilityLabel: "Case sensitive",
            action: #selector(caseSensitiveToggleClicked(_:))
        )
        searchToggleStrip.addArrangedSubview(caseSensitiveToggle)

        // Regex toggle — matches the preview/editor find bar icon
        setupToggleButton(
            regexToggle,
            symbolName: "ellipsis.curlybraces",
            accessibilityLabel: "Regular expression",
            action: #selector(regexToggleClicked(_:))
        )
        searchToggleStrip.addArrangedSubview(regexToggle)

        // Clear button — clears the search text field
        setupToggleButton(
            searchClearButton,
            symbolName: "xmark.circle.fill",
            accessibilityLabel: "Clear search",
            action: #selector(searchClearButtonClicked(_:))
        )
        searchClearButton.isHidden = true
        searchToggleStrip.addArrangedSubview(searchClearButton)

        // Add inside the search text field's coordinate space
        addSubview(searchToggleStrip)

        // Anchored to the trailing edge of the search text field, inside the bezel
        NSLayoutConstraint.activate([
            searchToggleStrip.trailingAnchor.constraint(equalTo: searchTextField.trailingAnchor, constant: -2),
            searchToggleStrip.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
        ])
    }

    /// Configures a toggle button with consistent styling.
    private func setupToggleButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.title = ""
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Search Mode Enter / Exit

    /// Enters deep search mode — hides breadcrumbs, shows search field + toggle icons.
    /// The search button stays visible as a toggle to exit search mode.
    func enterSearchMode() {
        guard !isSearchMode else { return }
        isSearchMode = true

        // Exit edit mode if active
        if isEditMode { exitEditMode() }

        // Hide normal breadcrumb UI
        scrollView.isHidden = true

        // Hide non-search action buttons, keep search button visible as toggle
        viewModeButton.isHidden = true
        thumbnailSizeButton.isHidden = true
        terminalButton.isHidden = true
        newFileButton.isHidden = true

        // Show search UI + idle status icon
        searchTextField.isHidden = false
        searchToggleStrip.isHidden = false
        searchStatusIcon.isHidden = false
        searchTextField.stringValue = ""

        // Focus the search field
        window?.makeFirstResponder(searchTextField)

        // Highlight the search button to indicate active state
        let theme = ThemeManager.shared.activeTheme
        searchButton.contentTintColor = theme.chromeAccent
        updateSearchToggleAppearance()

        delegate?.breadcrumbBarDidEnterSearchMode(self)
    }

    /// Exits deep search mode — restores breadcrumbs and normal action strip.
    func exitSearchMode() {
        guard isSearchMode else { return }
        isSearchMode = false

        // Hide search UI + spinner/icon
        searchTextField.isHidden = true
        searchToggleStrip.isHidden = true
        searchSpinner.stopAnimation(nil)
        searchSpinner.isHidden = true
        searchStatusIcon.isHidden = true
        searchTextField.stringValue = ""

        // Restore breadcrumb UI and action buttons
        scrollView.isHidden = false
        viewModeButton.isHidden = false
        terminalButton.isHidden = false
        newFileButton.isHidden = false
        // thumbnailSizeButton visibility managed by updateViewMode()

        // Un-highlight the search button
        let theme = ThemeManager.shared.activeTheme
        searchButton.contentTintColor = theme.chromeText

        // Reset search state
        searchMode = .filename
        searchOptions = SearchOptions()

        // Return focus to the window content
        window?.makeFirstResponder(window?.contentView)

        delegate?.breadcrumbBarDidExitSearchMode(self)
    }

    /// Swaps between spinner (searching) and static icon (idle) left of the search field.
    /// Called by FilePanelViewController when viewModel.isSearching changes.
    func updateSearchingState(_ isSearching: Bool) {
        guard isSearchMode else { return }

        if isSearching {
            searchStatusIcon.isHidden = true
            searchSpinner.isHidden = false
            searchSpinner.startAnimation(nil)
        } else {
            searchSpinner.stopAnimation(nil)
            searchSpinner.isHidden = true
            searchStatusIcon.isHidden = false
        }

        // Tint the status icon to match theme
        let theme = ThemeManager.shared.activeTheme
        searchStatusIcon.contentTintColor = theme.chromeTextSecondary
    }

    /// Updates toggle button tint colors based on active search state.
    private func updateSearchToggleAppearance() {
        let theme = ThemeManager.shared.activeTheme
        let activeColor = theme.chromeAccent
        let inactiveColor = theme.chromeText

        // Mode toggle: filled icon when content mode, outline when filename mode
        let modeSymbol = searchMode == .content ? "doc.text.fill" : "doc.text"
        searchModeToggle.image = NSImage(
            systemSymbolName: modeSymbol,
            accessibilityDescription: searchMode == .content ? "Search content" : "Search filenames"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        searchModeToggle.contentTintColor = searchMode == .content ? activeColor : inactiveColor

        caseSensitiveToggle.contentTintColor = searchOptions.caseSensitive ? activeColor : inactiveColor
        regexToggle.contentTintColor = searchOptions.regex ? activeColor : inactiveColor
        searchClearButton.contentTintColor = theme.chromeTextSecondary
    }

    /// Emits the current search query with mode and options to the delegate.
    private func emitSearchQuery() {
        let query = searchTextField.stringValue
        delegate?.breadcrumbBar(
            self,
            didChangeSearchQuery: query,
            mode: searchMode,
            options: searchOptions
        )
    }

    // MARK: - Search Toggle Actions

    @objc private func searchModeToggleClicked(_ sender: NSButton) {
        searchMode = (searchMode == .filename) ? .content : .filename
        updateSearchToggleAppearance()
        emitSearchQuery()
    }

    @objc private func caseSensitiveToggleClicked(_ sender: NSButton) {
        searchOptions.caseSensitive.toggle()
        updateSearchToggleAppearance()
        emitSearchQuery()
    }

    @objc private func regexToggleClicked(_ sender: NSButton) {
        searchOptions.regex.toggle()
        updateSearchToggleAppearance()
        emitSearchQuery()
    }

    @objc private func searchClearButtonClicked(_ sender: NSButton) {
        searchTextField.stringValue = ""
        searchClearButton.isHidden = true
        emitSearchQuery()
        window?.makeFirstResponder(searchTextField)
    }

    /// Shows or hides the clear button based on whether the search field has text.
    private func updateSearchClearButtonVisibility() {
        searchClearButton.isHidden = searchTextField.stringValue.isEmpty
    }

    // MARK: - Update

    /// Rebuilds breadcrumb segments from the given path and ghost state.
    func update(url: URL, ghostComponents: [String], ghostBaseURL: URL?) {
        self.currentURL = url
        self.ghostComponents = ghostComponents
        self.ghostBaseURL = ghostBaseURL

        guard !isEditMode, !isSearchMode else { return }
        rebuildSegments()
    }

    /// Reconstructs all segment views from current state.
    private func rebuildSegments() {
        // Remove existing segments
        segmentContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let url = currentURL else { return }

        let pathComponents = url.pathComponents
        var segments: [BreadcrumbSegmentView] = []

        // Build segments for each component of the current path
        for (index, component) in pathComponents.enumerated() {
            let displayName = component == "/" ? "/" : component
            let segmentURL = buildURL(from: pathComponents, upTo: index)
            let segment = BreadcrumbSegmentView(
                title: displayName,
                url: segmentURL,
                isGhost: false
            )
            segment.delegate = self
            segments.append(segment)
        }

        // Add ghost segments (capped at maxGhostSegments, already enforced by ViewModel)
        for (index, name) in ghostComponents.enumerated() {
            guard let ghostURL = resolveGhostURL(at: index) else { continue }
            let segment = BreadcrumbSegmentView(
                title: name,
                url: ghostURL,
                isGhost: true
            )
            segment.delegate = self
            segments.append(segment)
        }

        // Layout segments horizontally using Auto Layout.
        // The trailing constraint on the last segment sizes the document view
        // to its content, enabling the scroll view to scroll when segments overflow.
        var previousAnchor = segmentContainer.leadingAnchor
        for (index, segment) in segments.enumerated() {
            segmentContainer.addSubview(segment)
            var constraints = [
                segment.leadingAnchor.constraint(equalTo: previousAnchor, constant: previousAnchor == segmentContainer.leadingAnchor ? 0 : 2),
                segment.centerYAnchor.constraint(equalTo: segmentContainer.centerYAnchor),
            ]
            // Pin the last segment's trailing edge to the container so it
            // defines the document view's full width for the scroll view.
            if index == segments.count - 1 {
                constraints.append(
                    segment.trailingAnchor.constraint(equalTo: segmentContainer.trailingAnchor)
                )
            }
            NSLayoutConstraint.activate(constraints)
            previousAnchor = segment.trailingAnchor
        }

        // Auto-scroll to the rightmost segment (current directory).
        scrollToEnd()
    }

    /// Scrolls the breadcrumb scroll view to show the rightmost segment.
    private func scrollToEnd() {
        // Defer to the next layout pass so constraints have resolved.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let clipView = self.scrollView.contentView as? NSClipView else { return }
            let docWidth = self.segmentContainer.frame.width
            let clipWidth = clipView.bounds.width
            if docWidth > clipWidth {
                clipView.scroll(to: NSPoint(x: docWidth - clipWidth, y: 0))
                self.scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    // MARK: - Path Helpers

    /// Builds a URL from path components up to the given index.
    private func buildURL(from components: [String], upTo index: Int) -> URL {
        if index == 0 { return URL(fileURLWithPath: "/") }
        let path = "/" + components[1...index].joined(separator: "/")
        return URL(fileURLWithPath: path)
    }

    /// Resolves the full URL for a ghost component at the given index.
    private func resolveGhostURL(at index: Int) -> URL? {
        guard let base = ghostBaseURL, index < ghostComponents.count else { return nil }
        var url = base
        for i in 0...index {
            url = url.appendingPathComponent(ghostComponents[i])
        }
        return url
    }

    // MARK: - Edit Mode

    /// Enters edit mode — shows a text field with the current path for direct typing.
    func enterEditMode() {
        guard !isEditMode, let url = currentURL else { return }
        isEditMode = true
        scrollView.isHidden = true
        editField.isHidden = false
        editField.activate(with: url.path)
    }

    /// Exits edit mode — returns to breadcrumb segment display.
    func exitEditMode() {
        guard isEditMode else { return }
        isEditMode = false
        editField.deactivate()
        editField.isHidden = true
        scrollView.isHidden = false
    }

    /// Enters edit mode in FAYT filter configuration — path with trailing `/`, cursor at end.
    /// Optionally appends initial characters (from just-start-typing activation).
    func enterFilterMode(initialText: String = "") {
        guard !isEditMode, let url = currentURL else { return }
        isEditMode = true
        scrollView.isHidden = true
        editField.isHidden = false
        editField.activateForFilter(directoryPath: url.path, initialText: initialText)
    }

    // MARK: - Filter Pill

    /// Shows a filter pill badge after the last breadcrumb segment.
    func showFilterPill(text: String) {
        clearFilterPill()

        let pill = FilterPillView(text: text)
        pill.onDismiss = { [weak self] in
            guard let self else { return }
            self.clearFilterPill()
            self.delegate?.breadcrumbBarDidClearFilter(self)
        }
        filterPill = pill
        segmentContainer.addSubview(pill)

        // Position the pill after existing segment views
        let lastSegment = segmentContainer.subviews
            .compactMap { $0 as? BreadcrumbSegmentView }
            .last

        if let anchor = lastSegment {
            NSLayoutConstraint.activate([
                pill.leadingAnchor.constraint(equalTo: anchor.trailingAnchor, constant: 4),
                pill.centerYAnchor.constraint(equalTo: segmentContainer.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                pill.leadingAnchor.constraint(equalTo: segmentContainer.leadingAnchor),
                pill.centerYAnchor.constraint(equalTo: segmentContainer.centerYAnchor),
            ])
        }
    }

    /// Removes the filter pill badge from the breadcrumb bar.
    func clearFilterPill() {
        filterPill?.removeFromSuperview()
        filterPill = nil
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        for button in [viewModeButton, thumbnailSizeButton, terminalButton, searchButton, newFileButton] where !button.isHidden {
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

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        // Click on empty space (not on a segment or action strip) enters filter mode
        let location = convert(event.locationInWindow, from: nil)

        // Don't enter edit mode when clicking the action strip area
        let actionStripLocation = actionStrip.convert(event.locationInWindow, from: nil)
        let hitActionStrip = actionStrip.hitTest(actionStripLocation)

        // Check for filter pill click directly (the pill can extend beyond
        // segmentContainer bounds, so segmentContainer.hitTest misses it).
        if let pill = filterPill {
            let pillLocation = pill.convert(event.locationInWindow, from: nil)
            if pill.bounds.contains(pillLocation) {
                // Dismiss the pill — clear filter and return to normal breadcrumbs.
                clearFilterPill()
                delegate?.breadcrumbBarDidClearFilter(self)
                return
            }
        }

        let hitView = segmentContainer.hitTest(segmentContainer.convert(location, from: self))

        if hitActionStrip != nil {
            super.mouseDown(with: event)
        } else if hitView == segmentContainer || hitView == nil {
            enterFilterMode()
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - Actions

    @objc private func viewModeButtonClicked(_ sender: NSButton) {
        delegate?.breadcrumbBarDidRequestViewModeCycle(self)
    }

    @objc private func thumbnailSizeButtonClicked(_ sender: NSButton) {
        delegate?.breadcrumbBarDidRequestThumbnailSizeCycle(self)
    }

    @objc private func terminalButtonClicked(_ sender: NSButton) {
        delegate?.breadcrumbBarDidRequestTerminal(self)
    }

    @objc private func searchButtonClicked(_ sender: NSButton) {
        if isSearchMode {
            exitSearchMode()
        } else {
            enterSearchMode()
        }
    }

    @objc private func newFileButtonClicked(_ sender: NSButton) {
        delegate?.breadcrumbBarDidRequestNewFile(self, anchorView: sender)
    }

    // MARK: - View Mode Updates

    /// Updates the view mode button icon and thumbnail size button visibility.
    /// Called by FilePanelViewController when the view mode changes.
    func updateViewMode(_ mode: ViewMode, thumbnailSize: ThumbnailSize) {
        viewModeButton.image = NSImage(
            systemSymbolName: mode.symbolName,
            accessibilityDescription: "View mode: \(mode.rawValue)"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )

        thumbnailSizeButton.isHidden = (mode != .thumbnail)
        thumbnailSizeButton.image = NSImage(
            systemSymbolName: thumbnailSize.symbolName,
            accessibilityDescription: "Thumbnail size: \(thumbnailSize.rawValue)"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
    }

    // MARK: - Theme

    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        viewModeButton.contentTintColor = theme.chromeText
        thumbnailSizeButton.contentTintColor = theme.chromeText
        terminalButton.contentTintColor = theme.chromeText
        searchButton.contentTintColor = isSearchMode ? theme.chromeAccent : theme.chromeText
        newFileButton.contentTintColor = theme.chromeText
        filterPill?.applyTheme()
        segmentContainer.subviews
            .compactMap { $0 as? BreadcrumbSegmentView }
            .forEach { $0.applyTheme() }

        // Search mode styling
        searchTextField.textColor = theme.chromeText
        searchTextField.backgroundColor = theme.explorerBackground
        searchTextField.font = FontManager.shared.activeFont.withSize(12)
        searchStatusIcon.contentTintColor = theme.chromeTextSecondary
        if isSearchMode {
            updateSearchToggleAppearance()
        }
    }
}

// MARK: - BreadcrumbSegmentDelegate

extension BreadcrumbBarView: BreadcrumbSegmentDelegate {

    func breadcrumbSegmentClicked(url: URL) {
        exitEditMode()
        delegate?.breadcrumbBar(self, didNavigateTo: url)
    }

    func breadcrumbSegmentDropdownRequested(segment: BreadcrumbSegmentView, at url: URL) {
        // Request siblings for the parent of this segment
        let parentURL = url.deletingLastPathComponent()
        delegate?.breadcrumbBar(self, requestSiblingsFor: parentURL) { [weak self] siblings in
            guard let self else { return }
            self.showDropdownMenu(for: segment, parentURL: parentURL, siblings: siblings)
        }
    }

    /// Presents an NSMenu anchored to the segment with sibling directory names.
    private func showDropdownMenu(
        for segment: BreadcrumbSegmentView,
        parentURL: URL,
        siblings: [String]
    ) {
        let menu = NSMenu()
        menu.font = FontManager.shared.activeFont.withSize(12)
        for name in siblings {
            let item = NSMenuItem(title: name, action: #selector(dropdownItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = parentURL.appendingPathComponent(name)
            menu.addItem(item)
        }

        let point = NSPoint(x: 0, y: segment.bounds.maxY)
        menu.popUp(positioning: nil, at: point, in: segment)
    }

    @objc private func dropdownItemSelected(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        delegate?.breadcrumbBar(self, didNavigateTo: url)
    }
}

// MARK: - BreadcrumbEditFieldDelegate

extension BreadcrumbBarView: BreadcrumbEditFieldDelegate {

    func breadcrumbEditFieldDidConfirm(path: String) {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            exitEditMode()
            delegate?.breadcrumbBar(self, didNavigateTo: url)
        }
    }

    func breadcrumbEditFieldDidCancel() {
        exitEditMode()
        delegate?.breadcrumbBarDidClearFilter(self)
    }

    func breadcrumbEditFieldDidChangeFilter(_ filterText: String) {
        delegate?.breadcrumbBar(self, didChangeFilter: filterText)
    }

    func breadcrumbEditFieldDidConfirmFilter(_ filterText: String) {
        exitEditMode()
        if !filterText.isEmpty {
            showFilterPill(text: filterText)
            delegate?.breadcrumbBar(self, didConfirmFilter: filterText)
        }
    }

    func breadcrumbEditFieldRequestAutocomplete(
        directory: URL,
        prefix: String,
        completion: @escaping ([String]) -> Void
    ) {
        delegate?.breadcrumbBar(self, requestSiblingsFor: directory) { siblings in
            let lowPrefix = prefix.lowercased()
            let matches = siblings.filter { $0.lowercased().hasPrefix(lowPrefix) }
            completion(matches)
        }
    }
}

// MARK: - NSTextFieldDelegate (Search Text Field)

extension BreadcrumbBarView: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              textField === searchTextField,
              isSearchMode else { return }
        updateSearchClearButtonVisibility()
        // Search is executed on Enter, not on every keystroke.
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchTextField, isSearchMode else { return false }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape exits search mode
            exitSearchMode()
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Enter executes the search
            emitSearchQuery()
            return true
        }

        return false
    }
}
