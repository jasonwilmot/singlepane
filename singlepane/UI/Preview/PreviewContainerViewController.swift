// PreviewContainerViewController.swift
// Multi-file tabbed preview/editor container.
// Each open file gets a persistent tab in the file tab bar.
// Read/Edit mode switching is handled via toolbar buttons in the tab bar row.
//
// Shared child VCs (editor, markdown preview, code preview, media player)
// are reused across tabs — per-tab state is saved/restored on switch via
// PreviewTabState for performance.
//
// Routing logic:
//   • Markdown/HTML → Preview + Editor modes (Read/Edit buttons toggle)
//   • Text/source files → Editor only (no Read button)
//   • Images/PDF/media → special viewers (read-only)
//
// For markdown files, a toggleable outline column shows heading navigation.
// Toolbar buttons (Read/Edit/Save/Outline/Copy) sit in the file tab bar row.

import AppKit
import UniformTypeIdentifiers

/// The two modes available in the preview panel.
/// Internal mode for which view is currently displayed.
private enum PreviewMode {
    case preview
    case editor
}

/// Adapter that forwards TabBarDelegate calls from the file tab bar
/// to PreviewContainerViewController with file-tab-specific method names.
/// Needed because both the file tab bar and the mode tab bar use the same
/// TabBarDelegate protocol, and the container must distinguish the sender.
@MainActor
private final class FileTabBarDelegateAdapter: TabBarDelegate {
    weak var container: PreviewContainerViewController?

    func tabBarDidSelectTab(at index: Int) {
        container?.fileTabDidSelect(at: index)
    }
    func tabBarDidCloseTab(at index: Int) {
        container?.fileTabDidClose(at: index)
    }
    func tabBarDidDoubleClickTab(at index: Int) {
        container?.fileTabDidDoubleClick(at: index)
    }
    func tabBarDidReorderTab(from oldIndex: Int, to newIndex: Int) {
        container?.fileTabDidReorder(from: oldIndex, to: newIndex)
    }
    func tabBarDidRequestNewTab() {
        // No "+" button — file tabs are created by selecting files
    }
}

@MainActor
final class PreviewContainerViewController: NSViewController, FilePanelSelectionDelegate {

    // MARK: - File Tab Bar

    /// Tab bar showing one tab per open file (full style with close buttons).
    private let fileTabBar: TabBarView = {
        let bar = TabBarView()
        bar.showAddButton = false
        bar.tabItemStyle = .full
        bar.allowCloseLastTab = true
        bar.delegateHandlesClose = true
        bar.drawsOwnBackground = true
        return bar
    }()

    /// Delegate adapter for the file tab bar (forwards to fileTabDid* methods).
    private let fileTabBarAdapter = FileTabBarDelegateAdapter()

    /// Per-tab state — one entry per open file tab.
    private var tabs: [PreviewTabState] = []

    /// Index of the currently active file tab, or -1 when no tabs are open.
    private var activeTabIndex: Int = -1

    /// The currently active tab state, if any.
    private var activeTab: PreviewTabState? {
        guard tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }

    // MARK: - Toolbar Buttons

    /// Buttons in the tab bar row — consolidated from child VC toolbars.
    /// Wrapped in a stack view so hidden buttons don't occupy layout space.
    /// Smaller symbol config so icons breathe inside the button bezel.
    private static let buttonSymbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)

    private let readButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "book", accessibilityDescription: "Read")?
            .withSymbolConfiguration(buttonSymbolConfig)
        btn.title = "Read"
        btn.imagePosition = .imageLeading
        return btn
    }()
    private let editButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")?
            .withSymbolConfiguration(buttonSymbolConfig)
        btn.title = "Edit"
        btn.imagePosition = .imageLeading
        return btn
    }()
    private let saveButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")?
            .withSymbolConfiguration(buttonSymbolConfig)
        btn.title = "Save"
        btn.imagePosition = .imageLeading
        return btn
    }()
    private let outlineButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Outline")?
            .withSymbolConfiguration(buttonSymbolConfig)
        btn.title = ""
        btn.imagePosition = .imageOnly
        return btn
    }()
    private let copyButton: NSButton = {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?
            .withSymbolConfiguration(buttonSymbolConfig)
        btn.title = ""
        btn.imagePosition = .imageOnly
        return btn
    }()
    private let buttonStack = PointerCursorStackView()


    // MARK: - Panel Shift

    /// Shift arrow buttons for reordering the preview panel relative to neighbors.
    private let shiftArrows = PanelShiftArrowView(panelType: .preview)

    /// Delegate for panel swap requests. Set by RootSplitViewController.
    weak var shiftDelegate: PanelShiftDelegate? {
        didSet { shiftArrows.shiftDelegate = shiftDelegate }
    }

    /// Wrapper for all content below the tab bar row — dimmed on focus loss
    /// while the tab row stays at full opacity.
    let contentArea = NSView()

    /// NSSplitView holding the outline column (left) and main content (right).
    private let splitView = NSSplitView()

    /// The outline column showing markdown heading navigation.
    private let outlineView = MarkdownOutlineView()

    /// The main content area where child VC views are placed.
    private let mainContentView = NSView()

    /// Always-visible search bar for finding text in the content panel.
    private let contentFindBar = ContentFindBarView()

    /// Status bar at the bottom of the editor showing cursor position, encoding, etc.
    private let editorStatusBar = EditorStatusBarView()

    /// Floating zoom controls overlay for image/PDF preview.
    private let zoomControls = PreviewZoomControlsView()

    private let markdownPreview = MarkdownPreviewViewController()
    private let codePreview = CodePreviewViewController()
    private let editor = EditorViewController()
    private let mediaPlayer = MediaPlayerViewController()

    private var currentMode: PreviewMode = .preview

    /// When true, the Preview tab shows `codePreview` instead of `markdownPreview`.
    private var useCodePreview = false

    /// Tracks the most recently selected file for use when switching to editor mode.
    private var lastSelectedFileURL: URL?

    /// Whether the current file is markdown (controls outline and button visibility).
    private var isMarkdownFile = false

    /// True when the user explicitly chose editor mode for a previewable file
    /// (markdown/HTML). Prevents editor-only text files from sticking the mode.
    private var userChoseEditor = false

    /// Global toggle for the outline column — when enabled, the outline shows
    /// for any markdown file. Non-markdown files collapse the column visually
    /// but the preference persists so it reappears on the next markdown tab.
    private var isOutlineEnabled = false

    /// Whether the editor has unsaved changes (controls Save button highlight).
    private var hasUnsavedChanges = false

    /// Suppresses dirty tracking during programmatic file loads.
    private var isLoadingFile = false

    /// Remembered outline width for restore after toggle.
    private var lastOutlineWidth: CGFloat = 200

    /// Find bar top anchored to the file tab bar.
    private var findBarTopToTabBar: NSLayoutConstraint!

    /// Dynamic height constraint for the find bar — updated when replace row toggles.
    private var findBarHeightConstraint: NSLayoutConstraint!

    // MARK: - Search State

    /// Match ranges in the active NSTextView.
    private var searchMatchRanges: [NSRange] = []

    /// Current match index (0-based).
    private var currentSearchMatchIndex: Int = 0

    /// Whether the current search is targeting the WKWebView.
    private var isSearchingWebView = false

    /// Total match count in the WKWebView.
    private var webViewMatchCount = 0

    /// Current match index in the WKWebView (0-based).
    private var webViewCurrentMatchIndex = 0

    /// Whether the current search is targeting a memory-mapped file.
    private var isSearchingMmap = false

    /// Match positions from mmap search (byte offset + length pairs).
    private var mmapSearchMatches: [(byteOffset: Int, length: Int)] = []

    /// Current match index in mmap search (0-based).
    private var mmapCurrentMatchIndex = 0

    /// Debounce timer for live outline updates during editor text changes.
    private var outlineUpdateTimer: Timer?

    /// Cancellation token for in-flight file load operations.
    /// Cancelled when a new file is selected to prevent stale results.
    private var fileLoadTask: Task<Void, Never>?

    /// Spinner overlay shown when file loading takes >200ms.
    private var loadingSpinner: NSProgressIndicator?
    private var spinnerTimer: Timer?

    // MARK: - View Setup

    override func loadView() {
        let container = NSView()

        // File tab bar — full width with drawsOwnBackground for uniform color.
        // Reserve trailing space so tabs don't extend under the overlaid buttons.
        fileTabBar.trailingReservedWidth = 220
        fileTabBar.orientation = .horizontal
        fileTabBarAdapter.container = self
        fileTabBar.delegate = fileTabBarAdapter
        fileTabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fileTabBar)

        // Toolbar buttons — same bezel style as the tab bar "+" button.
        for button in [readButton, outlineButton, copyButton, editButton, saveButton] {
            button.bezelStyle = .accessoryBarAction
            button.font = FontManager.shared.activeFont.withSize(12)
            button.setContentHuggingPriority(.required, for: .horizontal)
        }

        readButton.target = self
        readButton.action = #selector(readButtonClicked)

        editButton.target = self
        editButton.action = #selector(editButtonClicked)

        saveButton.target = self
        saveButton.action = #selector(saveButtonClicked)
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command

        outlineButton.target = self
        outlineButton.action = #selector(outlineButtonClicked)

        copyButton.target = self
        copyButton.action = #selector(copyButtonClicked)

        // Stack view handles spacing; hidden views are detached automatically
        buttonStack.setViews([outlineButton, copyButton, readButton, editButton, saveButton], in: .leading)
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 6
        buttonStack.detachesHiddenViews = true
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonStack)

        // Shift arrows — trailing edge of tab bar row for panel reorder
        shiftArrows.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shiftArrows)

        // Content area — wraps everything below the tab bar row.
        // Dimmed on focus loss while the tab row stays at full opacity.
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentArea)

        // NSSplitView: outline column (left) + main content (right)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(splitView)

        // Add panes to split view — order determines left/right position
        outlineView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(outlineView)
        splitView.addSubview(mainContentView)

        // Content find bar — always visible, positioned between tab bar and content
        contentFindBar.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(contentFindBar)

        // Status bar — sits at the bottom, visible only in editor mode
        editorStatusBar.translatesAutoresizingMaskIntoConstraints = false
        editorStatusBar.isHidden = true
        contentArea.addSubview(editorStatusBar)

        // Zoom controls — floating overlay in bottom-right of main content, above status bar
        zoomControls.translatesAutoresizingMaskIntoConstraints = false
        zoomControls.isHidden = true
        zoomControls.delegate = self
        mainContentView.addSubview(zoomControls)

        // Find bar sits below top of content area
        findBarTopToTabBar = contentFindBar.topAnchor.constraint(equalTo: contentArea.topAnchor)
        findBarHeightConstraint = contentFindBar.heightAnchor.constraint(
            equalToConstant: ContentFindBarView.findOnlyHeight
        )

        NSLayoutConstraint.activate([
            // File tab bar — full width, buttons overlay on trailing edge.
            // trailingReservedWidth keeps internal scroll view from extending under buttons.
            fileTabBar.topAnchor.constraint(equalTo: container.topAnchor),
            fileTabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            fileTabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            fileTabBar.heightAnchor.constraint(equalToConstant: 32),

            // Shift arrows — absolute trailing edge of the row
            shiftArrows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            shiftArrows.centerYAnchor.constraint(equalTo: fileTabBar.centerYAnchor),

            // Button stack: trailing-aligned, to the left of shift arrows
            buttonStack.trailingAnchor.constraint(equalTo: shiftArrows.leadingAnchor, constant: -4),
            buttonStack.centerYAnchor.constraint(equalTo: fileTabBar.centerYAnchor),

            // Content area — fills below the tab bar row
            contentArea.topAnchor.constraint(equalTo: fileTabBar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Find bar row — height is dynamic based on replace row visibility
            contentFindBar.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            contentFindBar.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            findBarHeightConstraint,
            findBarTopToTabBar,

            // Split view fills between find bar and status bar
            splitView.topAnchor.constraint(equalTo: contentFindBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: editorStatusBar.topAnchor),

            // Status bar at the bottom — hidden when not in editor mode
            editorStatusBar.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            editorStatusBar.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            editorStatusBar.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            editorStatusBar.heightAnchor.constraint(equalToConstant: EditorStatusBarView.barHeight),

            // Zoom controls — floating bottom-right of the main content area
            zoomControls.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor, constant: -12),
            zoomControls.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor, constant: -12),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Add child view controllers before tab creation (addTab triggers showMode)
        addChild(markdownPreview)
        addChild(codePreview)
        addChild(editor)
        addChild(mediaPlayer)

        // Wire folder/file link clicks to the file explorer
        markdownPreview.onFolderLinkClicked = { [weak self] (url: URL) in
            self?.navigateExplorerToFolder(url)
        }
        markdownPreview.onFileLinkClicked = { [weak self] (url: URL) in
            self?.navigateExplorerToFile(url)
        }

        // Wire scroll spy callback from preview mode
        markdownPreview.onVisibleHeadingChanged = { [weak self] headingID in
            self?.handlePreviewScrollSpy(headingID: headingID)
        }

        // Wire zoom level changes to the floating controls
        markdownPreview.onZoomChanged = { [weak self] percentage in
            self?.zoomControls.updateZoomLevel(percentage)
        }

        // Wire editor text change for live outline updates, dirty tracking, and search refresh
        editor.onTextChanged = { [weak self] text in
            guard let self else { return }
            self.scheduleOutlineUpdate(for: text)
            self.reapplySearch()
            // Only mark dirty for real user edits, not programmatic file loads
            if !self.isLoadingFile {
                self.markActiveTabDirty()
            }
        }

        // Wire editor selection changes to the status bar cursor position
        editor.onSelectionChanged = { [weak self] line, column, selectionLength in
            self?.editorStatusBar.updateCursorPosition(
                line: line, column: column, selectionLength: selectionLength
            )
        }

        // Wire editor metadata changes (encoding, line endings, indent) to the status bar
        editor.onFileMetadataChanged = { [weak self] in
            self?.syncStatusBarFromEditor()
        }

        // Wire status bar delegate for menu actions
        editorStatusBar.delegate = self

        // Wire outline heading click
        outlineView.onHeadingSelected = { [weak self] heading, index in
            self?.handleOutlineHeadingClick(heading: heading, index: index)
        }

        // Apply initial theme/font and start observing changes
        fileTabBar.applyTheme()
        fileTabBar.startObservingTheme()
        fileTabBar.startObservingFont()
        contentFindBar.delegate = self
        contentFindBar.onReplaceVisibilityChanged = { [weak self] in
            self?.updateFindBarHeight()
        }
        startObservingTheme()
        startObservingFont()

        // Start with outline collapsed
        splitView.setPosition(0, ofDividerAt: 0)

        // Initial button state
        updateButtonVisibility()

        // Update preview tabs when a file is renamed in the explorer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileRenamed),
            name: .fileDidRename,
            object: nil
        )

        // Open newly created files in editor mode immediately
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileCreated),
            name: .fileDidCreate,
            object: nil
        )

        // No file tabs open yet — hide file tab content, show placeholder
        fileTabBar.showTabContent = false
        showMode(.preview)
        markdownPreview.showPlaceholder()
    }

    /// Updates any open preview tab whose file was renamed.
    @objc private func handleFileRenamed(_ notification: Notification) {
        guard let oldURL = notification.userInfo?["oldURL"] as? URL,
              let newURL = notification.userInfo?["newURL"] as? URL else { return }

        for (i, tab) in tabs.enumerated() {
            if tab.fileURL == oldURL {
                tab.fileURL = newURL
                fileTabBar.updateTabTitle(newURL.lastPathComponent, at: i)

                if i == activeTabIndex {
                    lastSelectedFileURL = newURL
                }
                break
            }
        }
    }

    /// Switches a newly created file's preview tab to editor mode.
    @objc private func handleFileCreated(_ notification: Notification) {
        guard let fileURL = notification.userInfo?["fileURL"] as? URL else { return }

        // Find the tab for this file (filePanelDidSelect already created it)
        guard let tabIndex = tabs.firstIndex(where: { $0.fileURL == fileURL }) else { return }

        let tab = tabs[tabIndex]
        tab.userChoseEditor = true
        tab.mode = .editor

        // If this is the active tab, switch the view to editor mode now
        if tabIndex == activeTabIndex {
            userChoseEditor = true
            switchToEditor(for: fileURL)
            updateButtonVisibility()
        }
    }

    // MARK: - Button Visibility

    /// Updates Read/Edit/Save/Outline/Copy button visibility and highlight state.
    /// All buttons are always visible — disabled when not applicable.
    /// Read: enabled in editor mode for previewable files.
    /// Edit: enabled in preview mode for previewable files.
    /// Save: enabled in editor mode.
    /// Outline: enabled for markdown files.
    /// Copy: enabled whenever a file is loaded.
    private func updateButtonVisibility() {
        let hasPreview = activeTab?.hasPreviewSupport ?? false
        let theme = ThemeManager.shared.activeTheme

        // Show Read in editor mode, Edit in preview mode — never both
        readButton.isHidden = currentMode != .editor
        editButton.isHidden = currentMode != .preview
        readButton.isEnabled = hasPreview
        editButton.isEnabled = hasPreview
        saveButton.isEnabled = currentMode == .editor
        outlineButton.isEnabled = isMarkdownFile
        copyButton.isEnabled = lastSelectedFileURL != nil

        // Match the system chrome color used by the tab bar "+" button.
        // Enabled buttons use default system tint (nil); disabled buttons are dimmed.
        let disabledTint = theme.chromeTextSecondary.withAlphaComponent(0.25)

        readButton.contentTintColor = readButton.isEnabled ? nil : disabledTint
        editButton.contentTintColor = editButton.isEnabled ? nil : disabledTint
        copyButton.contentTintColor = copyButton.isEnabled ? nil : disabledTint

        // Outline button: highlighted background when toggled on
        let highlightColor = theme.paletteColor(at: 6)
        applyButtonHighlight(
            outlineButton,
            highlighted: isOutlineEnabled && isMarkdownFile,
            activeColor: highlightColor
        )
        if !outlineButton.isEnabled {
            outlineButton.contentTintColor = disabledTint
        } else if !(isOutlineEnabled && isMarkdownFile) {
            outlineButton.contentTintColor = nil
        }

        // Save button: highlighted background when there are unsaved changes
        applyButtonHighlight(
            saveButton,
            highlighted: hasUnsavedChanges,
            activeColor: highlightColor
        )
        if !saveButton.isEnabled {
            saveButton.contentTintColor = disabledTint
        } else if !hasUnsavedChanges {
            saveButton.contentTintColor = nil
        }
    }

    /// Highlights a button by setting its layer background color.
    private func applyButtonHighlight(_ button: NSButton, highlighted: Bool, activeColor: NSColor) {
        button.wantsLayer = true
        if highlighted {
            button.contentTintColor = activeColor
            button.layer?.backgroundColor = activeColor.withAlphaComponent(0.15).cgColor
        } else {
            button.contentTintColor = nil
            button.layer?.backgroundColor = nil
        }
    }

    // MARK: - Zoom Controls

    /// Handles Cmd+=, Cmd+-, Cmd+0 for zoom when showing zoomable content.
    /// Returns true if the event was consumed.
    func handleZoomKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !zoomControls.isHidden
        else { return false }

        switch event.charactersIgnoringModifiers {
        case "+", "=":
            markdownPreview.zoomIn()
            return true
        case "-":
            markdownPreview.zoomOut()
            return true
        case "0":
            markdownPreview.resetZoom()
            return true
        default:
            return false
        }
    }

    /// Shows zoom controls when preview mode is showing zoomable content (image/PDF).
    /// Hides them for all other modes and content types.
    private func updateZoomControlsVisibility() {
        let shouldShow = currentMode == .preview
            && !useCodePreview
            && markdownPreview.isZoomableContent
        zoomControls.isHidden = !shouldShow
        if shouldShow {
            zoomControls.updateZoomLevel(markdownPreview.currentZoomPercentage)
            zoomControls.showAndRestartFadeTimer()
        }
    }

    // MARK: - Mode Switching

    private func showMode(_ mode: PreviewMode) {
        currentMode = mode

        // Remove all child views from main content area
        for child in children {
            child.view.removeFromSuperview()
        }

        // Add the selected mode's view
        let targetVC: NSViewController = switch mode {
        case .preview: useCodePreview ? codePreview : markdownPreview
        case .editor:  editor
        }

        targetVC.view.frame = mainContentView.bounds
        targetVC.view.autoresizingMask = [.width, .height]
        mainContentView.addSubview(targetVC.view)

        // Keep zoom controls on top of child views
        mainContentView.addSubview(zoomControls, positioned: .above, relativeTo: nil)

        // When switching to editor, auto-load the currently selected file if it's editable text
        if mode == .editor, let url = lastSelectedFileURL, isEditableTextFile(url) {
            isLoadingFile = true
            editor.loadFile(at: url)
            isLoadingFile = false
        }

        updateButtonVisibility()
        updateZoomControlsVisibility()

        // Enable replace toggle only in editor mode
        contentFindBar.setReplaceEnabled(mode == .editor)

        // Show/hide status bar based on mode
        editorStatusBar.isHidden = (mode != .editor)

        // Sync status bar data when entering editor mode
        if mode == .editor {
            syncStatusBarFromEditor()
            setupEditorScrollSpy()
        }

        // Re-apply search highlights in the new mode
        reapplySearch()

        // Stop spinner — synchronous loading is complete
        stopLoadingSpinner()
    }

    // MARK: - Editor-Only Mode

    /// Shows the editor directly with no tab bar for non-previewable file types.
    private func showEditorOnly(for url: URL) {

        collapseOutlineColumn()
        hasUnsavedChanges = false
        isLoadingFile = true
        editor.loadFile(at: url)
        isLoadingFile = false
        currentMode = .editor
        userChoseEditor = false

        // Remove all child views and show editor
        for child in children {
            child.view.removeFromSuperview()
        }
        editor.view.frame = mainContentView.bounds
        editor.view.autoresizingMask = [.width, .height]
        mainContentView.addSubview(editor.view)
        updateButtonVisibility()
        updateZoomControlsVisibility()
        contentFindBar.setReplaceEnabled(true)
        editorStatusBar.isHidden = false
        syncStatusBarFromEditor()
        reapplySearch()
        stopLoadingSpinner()
    }

    // MARK: - Media Playback

    private func showMediaPlayer(for url: URL) {
        // Remove all child views and show the media player directly
        for child in children {
            child.view.removeFromSuperview()
        }
        mediaPlayer.view.frame = mainContentView.bounds
        mediaPlayer.view.autoresizingMask = [.width, .height]
        mainContentView.addSubview(mediaPlayer.view)
        mediaPlayer.loadMedia(at: url)

        currentMode = .preview

        editorStatusBar.isHidden = true
        updateZoomControlsVisibility()

    }

    // MARK: - Code Preview

    private func showCodePreview(for url: URL) {
        useCodePreview = true
        codePreview.loadFile(at: url)

        showMode(.preview)
    }

    // MARK: - Edit / Preview Flow

    private func switchToEditor(for url: URL) {
        hasUnsavedChanges = false
        isLoadingFile = true
        editor.loadFile(at: url)
        isLoadingFile = false

        showMode(.editor)
    }

    private func switchToPreview(for url: URL) {
        markdownPreview.loadMarkdownFile(at: url)

        showMode(.preview)
        // Refresh outline with saved content
        refreshOutline(for: url)
    }

    // MARK: - Outline Toggle

    /// Toggles the global outline preference on or off.
    /// When enabled, the outline shows for any markdown file.
    /// When a non-markdown file is active, the column collapses visually
    /// but the preference stays on.
    private func toggleOutline() {
        isOutlineEnabled = !isOutlineEnabled
        syncOutlineVisibility()
        updateButtonVisibility()
    }

    /// Syncs the outline column's visual state with the global toggle and
    /// current file type. Shows the column only when both the toggle is on
    /// and the active file is markdown.
    private func syncOutlineVisibility() {
        let shouldShow = isOutlineEnabled && isMarkdownFile
        if shouldShow {
            showOutlineColumn()
        } else {
            collapseOutlineColumn()
        }
    }

    /// Expands the outline column to the remembered width and populates headings.
    private func showOutlineColumn() {
        splitView.setPosition(lastOutlineWidth, ofDividerAt: 0)
        splitView.adjustSubviews()

        // Populate outline with current file's headings
        if let url = lastSelectedFileURL {
            refreshOutline(for: url)
        }
    }

    /// Collapses the outline column to zero width, remembering its size.
    private func collapseOutlineColumn() {
        let currentWidth = outlineView.frame.width
        if currentWidth > 10 {
            lastOutlineWidth = currentWidth
        }
        splitView.setPosition(0, ofDividerAt: 0)
        splitView.adjustSubviews()
    }

    // MARK: - Outline Data

    /// Parses headings from the given file URL and updates the outline.
    private func refreshOutline(for url: URL) {
        guard isOutlineEnabled, isMarkdownFile else { return }

        if currentMode == .editor {
            // Use the editor's live text
            let headings = MarkdownHeadingParser.parse(editor.text)
            outlineView.updateHeadings(headings)
        } else {
            // Read from disk for preview mode
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let headings = MarkdownHeadingParser.parse(text)
            outlineView.updateHeadings(headings)
        }
    }

    /// Debounced outline update triggered by editor text changes.
    private func scheduleOutlineUpdate(for text: String) {
        outlineUpdateTimer?.invalidate()
        outlineUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isOutlineEnabled else { return }
                let headings = MarkdownHeadingParser.parse(text)
                self.outlineView.updateHeadings(headings)
            }
        }
    }

    // MARK: - Outline Click-to-Navigate

    /// Handles a heading click in the outline — scrolls the active view to that heading.
    private func handleOutlineHeadingClick(heading: MarkdownHeading, index: Int) {
        if currentMode == .editor {
            // Editor mode: scroll NSTextView to the heading's character range
            editor.scrollToRange(heading.range)
        } else {
            // Preview mode: scroll WKWebView via JavaScript anchor
            markdownPreview.scrollToHeading(id: "heading-\(index)")
        }
    }

    // MARK: - Scroll Spy

    /// Sets up scroll observation on the editor's scroll view for scroll spy.
    /// Removes any previous observer to avoid duplicates on repeated mode switches.
    private func setupEditorScrollSpy() {
        guard let editorScrollView = editor.editorScrollView else { return }

        // Remove previous observer to prevent duplicates
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: editorScrollView.contentView
        )

        editorScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editorDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: editorScrollView.contentView
        )
    }

    /// Called when the editor scroll view scrolls — updates the active heading in the outline.
    @objc private func editorDidScroll(_ notification: Notification) {
        guard isOutlineEnabled, currentMode == .editor else { return }
        guard let scrollView = editor.editorScrollView else { return }

        let headings = outlineView.currentHeadings
        guard !headings.isEmpty else { return }

        // Find the heading closest to the top of the visible area
        let visibleRect = scrollView.contentView.documentVisibleRect
        let visibleTop = visibleRect.origin.y

        var bestIndex = 0
        for (i, heading) in headings.enumerated() {
            // Get the y position of the heading's character range in the text view
            guard let layoutManager = (scrollView.documentView as? NSTextView)?.layoutManager,
                  let textContainer = (scrollView.documentView as? NSTextView)?.textContainer else { break }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: heading.range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            if rect.origin.y <= visibleTop + 20 {
                bestIndex = i
            } else {
                break
            }
        }

        outlineView.setActiveHeading(at: bestIndex)
    }

    /// Called when the preview's scroll spy reports a visible heading change.
    private func handlePreviewScrollSpy(headingID: String) {
        guard isOutlineEnabled, currentMode == .preview else { return }

        // Parse the heading index from the ID (e.g., "heading-3" → 3)
        guard headingID.hasPrefix("heading-"),
              let index = Int(headingID.dropFirst("heading-".count)) else { return }

        outlineView.setActiveHeading(at: index)
    }

    // MARK: - Find Bar Height

    /// Updates the find bar height constraint to match the current replace row visibility.
    private func updateFindBarHeight() {
        findBarHeightConstraint.constant = contentFindBar.currentHeight
    }

    // MARK: - Theme

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

    private func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        updateButtonVisibility()
    }

    // MARK: - Font

    private func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.startObservingFont()
            }
        }
    }

    private func applyFont() {
        let font = FontManager.shared.activeFont.withSize(12)
        for button in [readButton, outlineButton, copyButton, editButton, saveButton] {
            button.font = font
        }
    }

    // MARK: - Status Bar

    /// Syncs the status bar display with the editor's current file metadata.
    private func syncStatusBarFromEditor() {
        editorStatusBar.updateEncoding(editor.fileEncoding)
        editorStatusBar.updateLineEndings(editor.lineEndings)
        editorStatusBar.updateIndentStyle(editor.indentStyle)
        editorStatusBar.updateLanguage(editor.currentLanguage)
        editorStatusBar.updateWordWrap(editor.wordWrapEnabled)
    }

    // MARK: - File Type Detection

    /// Returns true if the file is a text-based format suitable for the editor.
    private func isEditableTextFile(_ url: URL) -> Bool {
        if isKnownTextExtension(url) { return true }
        let utType = UTType(filenameExtension: url.pathExtension.lowercased())
        guard let type = utType else { return false }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode)
            || type.conforms(to: .yaml) || type.conforms(to: .json)
            || type.conforms(to: .xml) || type.conforms(to: .propertyList)
    }

    /// Checks if the file is one we have syntax highlighting for,
    /// covering cases where UTType doesn't classify the file as text.
    private func isKnownTextExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension
        if ext.isEmpty {
            return CodeSyntaxHighlighter.language(forFilename: url.lastPathComponent) != "text"
        }
        let lang = CodeSyntaxHighlighter.language(for: ext)
        return lang != "text" || ext.lowercased() == "txt"
    }

    /// Returns true if the file supports a rendered preview (markdown or HTML).
    private func hasPreviewSupport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "html" || ext == "htm"
    }

    /// Returns true if the file is a markdown file.
    private func isMarkdownExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    // MARK: - Shift Arrow Update

    /// Updates shift arrow visibility and tooltips from computed state.
    func updateShiftArrows(_ state: ShiftArrowState) {
        shiftArrows.update(state)
    }

    // MARK: - FilePanelSelectionDelegate

    func filePanelDidSelect(fileURL: URL?) {
        guard let url = fileURL else { return }

        // Folders should not update the preview/editor — keep showing the last file.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return
        }

        // If the file already has an open tab, focus it instead of creating a duplicate
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            switchToFileTab(at: existingIndex)
            return
        }

        // Save current tab state before creating a new one
        saveActiveTabState()

        // Create a new tab state for this file
        let tabState = PreviewTabState(fileURL: url)
        tabState.isMarkdownFile = isMarkdownExtension(url)
        tabState.hasPreviewSupport = hasPreviewSupport(url)
        tabState.useCodePreview = false
        tabState.userChoseEditor = false

        tabs.append(tabState)
        activeTabIndex = tabs.count - 1

        // Show the file tab bar if this is the first tab
        if tabs.count == 1 {
            fileTabBar.showTabContent = true
        }

        // Add visual tab and select it
        fileTabBar.addTab(title: url.lastPathComponent)

        // New tabs always open in read mode for previewable files
        userChoseEditor = false

        // Load the file content into the shared VCs
        loadFileIntoViews(url)
    }

    // MARK: - File Tab Management

    /// Saves the current active tab's state from the shared VCs.
    private func saveActiveTabState() {
        guard let tab = activeTab else { return }
        tab.mode = currentMode == .editor ? PreviewTabMode.editor : PreviewTabMode.preview
        tab.useCodePreview = useCodePreview
        tab.userChoseEditor = userChoseEditor
        tab.hasUnsavedChanges = hasUnsavedChanges

        // Save editor state
        if currentMode == .editor {
            tab.dirtyText = hasUnsavedChanges ? editor.text : nil
            tab.editorCursorPosition = editor.editorTextView?.selectedRange().location ?? 0
            tab.editorScrollY = editor.editorScrollView?.contentView.bounds.origin.y ?? 0
        }

        // Save code preview scroll position
        if useCodePreview {
            tab.codePreviewScrollY = codePreview.previewScrollView?.contentView.bounds.origin.y ?? 0
        }
    }

    /// Switches to the file tab at the given index, saving/restoring state.
    private func switchToFileTab(at index: Int) {
        guard tabs.indices.contains(index), index != activeTabIndex else { return }

        // Clear search state before switching — each tab starts with a clean search
        clearSearchHighlights()
        contentFindBar.searchText = ""
        contentFindBar.updateCounter(current: 0, total: 0)

        saveActiveTabState()
        activeTabIndex = index
        fileTabBar.selectTabVisually(at: index)

        let tab = tabs[index]
        restoreTabState(tab)
    }

    /// Restores tab state into the shared VCs and loads the file.
    /// If the file no longer exists on disk, the tab is closed automatically.
    private func restoreTabState(_ tab: PreviewTabState) {
        // Check if the file still exists — close the tab if it was deleted externally
        if !FileManager.default.fileExists(atPath: tab.fileURL.path) {
            if let deadIndex = tabs.firstIndex(where: { $0 === tab }) {
                performTabClose(at: deadIndex)
            }
            return
        }

        // Apply tab-level flags
        isMarkdownFile = tab.isMarkdownFile
        useCodePreview = tab.useCodePreview
        userChoseEditor = tab.userChoseEditor
        hasUnsavedChanges = tab.hasUnsavedChanges
        lastSelectedFileURL = tab.fileURL

        // Load the file into the appropriate VCs
        loadFileIntoViews(tab.fileURL)

        // Restore editor state if we're in editor mode
        if tab.mode == PreviewTabMode.editor || (!tab.hasPreviewSupport && !useCodePreview) {
            // Restore dirty text if present
            if let dirtyText = tab.dirtyText {
                editor.editorTextView?.string = dirtyText
            }
            // Restore cursor position
            let cursor = tab.editorCursorPosition
            if let textView = editor.editorTextView,
               cursor <= (textView.string as NSString).length {
                textView.setSelectedRange(NSRange(location: cursor, length: 0))
            }
            // Restore scroll position after layout
            let scrollY = tab.editorScrollY
            DispatchQueue.main.async { [weak self] in
                self?.editor.editorScrollView?.contentView.scroll(
                    to: NSPoint(x: 0, y: scrollY)
                )
            }
        }

        // Restore code preview scroll position
        if useCodePreview {
            let scrollY = tab.codePreviewScrollY
            DispatchQueue.main.async { [weak self] in
                self?.codePreview.previewScrollView?.contentView.scroll(
                    to: NSPoint(x: 0, y: scrollY)
                )
            }
        }
    }

    /// Routes a file URL to the appropriate shared VCs based on file type.
    /// This is the core file-loading logic, extracted from the original
    /// filePanelDidSelect for reuse on tab creation and tab switching.
    private func loadFileIntoViews(_ url: URL) {
        // Cancel any in-flight file load from a previous selection
        fileLoadTask?.cancel()
        fileLoadTask = nil
        stopLoadingSpinner()

        lastSelectedFileURL = url

        let ext = url.pathExtension.lowercased()
        let utType = UTType(filenameExtension: ext)
        isMarkdownFile = isMarkdownExtension(url)

        // Reset code preview flag — only set by the text/source branch below
        useCodePreview = false
        mediaPlayer.stop()

        // Start spinner timer for large files (appears after 200ms if still loading)
        if url.fileSize >= FileSizeThreshold.normalLoad {
            startLoadingSpinnerTimer()
        }

        // Sync outline column: show for markdown when enabled, collapse otherwise
        syncOutlineVisibility()

        if ext == "md" || ext == "markdown" {
            // Markdown — supports both preview and edit modes.
            // Stay in editor only if the user explicitly chose it; otherwise show preview.
    
            if userChoseEditor {
                switchToEditor(for: url)
            } else {
                markdownPreview.loadMarkdownFile(at: url)
    
                showMode(.preview)
            }
            // Refresh outline if visible
            if isOutlineEnabled {
                refreshOutline(for: url)
            }
        } else if ext == "html" || ext == "htm" {
            // HTML — supports both preview and edit modes.
    
            if userChoseEditor {
                switchToEditor(for: url)
            } else {
                markdownPreview.loadHTMLFile(at: url)
    
                showMode(.preview)
            }
        } else if isKnownTextExtension(url) {
            // Known source code / text files → editor only, no preview tab.
            showEditorOnly(for: url)
        } else if let type = utType, type.conforms(to: .pdf) {
            // PDF → native WKWebView rendering (not editable)
    
            markdownPreview.loadPDFFile(at: url)

            showMode(.preview)
        } else if let type = utType, type.conforms(to: .audiovisualContent) {
            // Audio/video → media player
            showMediaPlayer(for: url)
        } else if let type = utType, type.conforms(to: .image) {
            // Images → display in webview (not editable)
    
            markdownPreview.loadImageFile(at: url)

            showMode(.preview)
        } else if let type = utType, type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            // Text/source files → editor only, no preview tab
            showEditorOnly(for: url)
        } else {
            // Unknown type → assume editable text
            showEditorOnly(for: url)
        }
    }

    // MARK: - File Tab Delegate (via adapter)

    /// Called when the user clicks a file tab — switches to that tab.
    func fileTabDidSelect(at index: Int) {
        switchToFileTab(at: index)
    }

    /// Called when the user double-clicks a file tab — navigates the top
    /// file explorer pane to the directory containing that tab's file.
    func fileTabDidDoubleClick(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let fileURL = tabs[index].fileURL
        let parentDir = fileURL.deletingLastPathComponent()
        navigateExplorerToFolder(parentDir)
    }

    /// Called when the user clicks the close button on a file tab.
    func fileTabDidClose(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]

        // Prompt if the tab has unsaved changes
        if tab.hasUnsavedChanges || (index == activeTabIndex && hasUnsavedChanges) {
            promptSaveBeforeClose(tabIndex: index)
            return
        }

        performTabClose(at: index)
    }

    /// Called when the user drags a file tab to a new position.
    func fileTabDidReorder(from oldIndex: Int, to newIndex: Int) {
        guard oldIndex != newIndex,
              tabs.indices.contains(oldIndex),
              newIndex >= 0, newIndex < tabs.count else { return }

        let tab = tabs.remove(at: oldIndex)
        tabs.insert(tab, at: newIndex)

        // Update active tab index to follow the active tab
        if activeTabIndex == oldIndex {
            activeTabIndex = newIndex
        } else if oldIndex < activeTabIndex && newIndex >= activeTabIndex {
            activeTabIndex -= 1
        } else if oldIndex > activeTabIndex && newIndex <= activeTabIndex {
            activeTabIndex += 1
        }
    }

    /// Shows a Save / Don't Save / Cancel alert before closing a dirty tab.
    private func promptSaveBeforeClose(tabIndex: Int) {
        let tab = tabs[tabIndex]
        let alert = NSAlert()
        alert.messageText = "Save changes to \"\(tab.fileURL.lastPathComponent)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard let window = view.window else {
            // No window — fall back to modal
            let response = alert.runModal()
            handleSavePromptResponse(response, tabIndex: tabIndex)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            self?.handleSavePromptResponse(response, tabIndex: tabIndex)
        }
    }

    /// Processes the save prompt response and closes the tab if appropriate.
    private func handleSavePromptResponse(_ response: NSApplication.ModalResponse, tabIndex: Int) {
        switch response {
        case .alertFirstButtonReturn:
            // Save — switch to the tab, save, then close
            if tabIndex == activeTabIndex {
                editor.saveFile()
            } else {
                // Save the dirty text directly to the file
                let tab = tabs[tabIndex]
                if let dirtyText = tab.dirtyText {
                    try? dirtyText.write(to: tab.fileURL, atomically: true, encoding: String.Encoding.utf8)
                }
            }
            performTabClose(at: tabIndex)
        case .alertSecondButtonReturn:
            // Don't Save — discard changes and close
            performTabClose(at: tabIndex)
        default:
            // Cancel — do nothing
            break
        }
    }

    /// Removes a tab from the array, removes the visual tab, and updates the UI.
    private func performTabClose(at index: Int) {
        tabs.remove(at: index)

        // Remove the visual tab from the tab bar
        fileTabBar.removeTab(at: index)

        if tabs.isEmpty {
            // No tabs left — show placeholder
            activeTabIndex = -1
            lastSelectedFileURL = nil
            isMarkdownFile = false
            hasUnsavedChanges = false
    
            collapseOutlineColumn()
            updateButtonVisibility()
            markdownPreview.showPlaceholder()
            editorStatusBar.isHidden = true
            fileTabBar.showTabContent = false
        } else {
            // Select the nearest tab
            let newIndex: Int
            if activeTabIndex == index {
                newIndex = min(index, tabs.count - 1)
            } else if activeTabIndex > index {
                newIndex = activeTabIndex - 1
            } else {
                newIndex = activeTabIndex
            }
            activeTabIndex = newIndex
            fileTabBar.selectTabVisually(at: newIndex)
            restoreTabState(tabs[newIndex])
        }
    }

    // MARK: - Dirty State Tracking

    /// Marks the active tab as having unsaved changes and updates the UI.
    private func markActiveTabDirty() {
        guard !hasUnsavedChanges else { return }
        hasUnsavedChanges = true
        activeTab?.hasUnsavedChanges = true
        updateButtonVisibility()

        // Update the file tab's status indicator to show dirty state
        if activeTabIndex >= 0 {
            fileTabBar.startSpinner(at: activeTabIndex)
        }
    }

    /// Clears the dirty state on the active tab after a save.
    private func clearActiveTabDirty() {
        hasUnsavedChanges = false
        activeTab?.hasUnsavedChanges = false
        activeTab?.dirtyText = nil
        updateButtonVisibility()

        // Restore the normal status indicator
        if activeTabIndex >= 0 {
            fileTabBar.stopSpinner(at: activeTabIndex)
        }
    }

    // MARK: - Explorer Navigation (Link Click Routing)

    /// Walks the parent chain to find RootSplitViewController and navigates
    /// the top file pane into the target folder.
    private func navigateExplorerToFolder(_ url: URL) {
        guard let root = findRootSplitViewController() else { return }
        root.explorerContainer?.topPane.openFolder(at: url)
    }

    /// Walks the parent chain to find RootSplitViewController and opens
    /// the target file in the top file pane (navigates to parent dir + selects).
    private func navigateExplorerToFile(_ url: URL) {
        guard let root = findRootSplitViewController() else { return }
        root.explorerContainer?.topPane.openFile(at: url)
    }

    private func findRootSplitViewController() -> RootSplitViewController? {
        var current: NSViewController? = parent
        while let vc = current {
            if let root = vc as? RootSplitViewController { return root }
            current = vc.parent
        }
        return nil
    }

    // MARK: - Actions

    @objc private func readButtonClicked() {
        guard let url = lastSelectedFileURL else { return }
        userChoseEditor = false
        activeTab?.userChoseEditor = false
        switchToPreview(for: url)
    }

    @objc private func editButtonClicked() {
        guard let url = lastSelectedFileURL else { return }
        userChoseEditor = true
        activeTab?.userChoseEditor = true
        switchToEditor(for: url)
    }

    @objc private func saveButtonClicked() {
        if let url = editor.saveFile() {
            clearActiveTabDirty()
            flashSaveConfirmation()
            // Stay in editor mode — just refresh the outline with the saved content
            if isOutlineEnabled {
                refreshOutline(for: url)
            }
        }
    }

    /// Flashes a brief green overlay on the content panel to confirm a successful save.
    private func flashSaveConfirmation() {
        let theme = ThemeManager.shared.activeTheme
        let overlay = NSView(frame: mainContentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = theme.paletteColor(at: 2).withAlphaComponent(0.15).cgColor
        mainContentView.addSubview(overlay)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            overlay.animator().alphaValue = 0
        } completionHandler: {
            overlay.removeFromSuperview()
        }
    }

    @objc private func outlineButtonClicked() {
        toggleOutline()
    }

    /// Copies the raw file contents to the clipboard with visual and audio feedback.
    @objc private func copyButtonClicked() {
        guard let url = lastSelectedFileURL else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            NSSound(named: "Morse")?.play()
            flashCopyFeedback()
        } catch {
            NSLog("Copy failed: \(error.localizedDescription)")
        }
    }

    /// Briefly flashes the content area with the theme accent color to confirm copy.
    private func flashCopyFeedback() {
        let overlay = NSView()
        overlay.wantsLayer = true
        let accentColor = ThemeManager.shared.activeTheme.paletteColor(at: 4)
        overlay.layer?.backgroundColor = accentColor.withAlphaComponent(0.15).cgColor
        overlay.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
        ])

        // Fade out and remove after a brief flash
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.removeFromSuperview()
        })
    }

    // MARK: - Loading Spinner

    /// Starts a delayed spinner that appears after 200ms if not cancelled.
    /// Used for large file loads that may take noticeable time.
    private func startLoadingSpinnerTimer() {
        spinnerTimer?.invalidate()
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showLoadingSpinner()
            }
        }
    }

    private func showLoadingSpinner() {
        guard loadingSpinner == nil else { return }

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        mainContentView.addSubview(spinner)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: mainContentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
        ])

        loadingSpinner = spinner
    }

    /// Removes the loading spinner and cancels the delayed timer.
    private func stopLoadingSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.removeFromSuperview()
        loadingSpinner = nil
    }

    // MARK: - Find Bar Focus

    /// Focuses the content find bar search field. Called by RootSplitVC on Cmd+F.
    func focusFindBar() {
        contentFindBar.focusSearchField()
    }

}

// MARK: - NSSplitViewDelegate

extension PreviewContainerViewController: NSSplitViewDelegate {

    /// Minimum width for the outline column.
    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        120
    }

    /// Maximum width for the outline column — no upper limit, user decides.
    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        proposedMaximumPosition
    }

    /// Only the outline column (left pane) is collapsible.
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === outlineView
    }

    /// Track outline width changes from user dragging.
    func splitViewDidResizeSubviews(_ notification: Notification) {
        let width = outlineView.frame.width
        if width > 10 {
            lastOutlineWidth = width
        }
    }
}

// MARK: - ContentFindBarDelegate

extension PreviewContainerViewController: ContentFindBarDelegate {

    func contentFindBarSearchTextDidChange(_ text: String) {
        performContentSearch(text)
    }

    func contentFindBarDidRequestNextMatch() {
        navigateToNextMatch()
    }

    func contentFindBarDidRequestPreviousMatch() {
        navigateToPreviousMatch()
    }

    func contentFindBarDidRequestFocusContent() {
        if let textView = activeTextView {
            view.window?.makeFirstResponder(textView)
        }
    }

    func contentFindBarDidRequestReplace(_ replacementText: String) {
        replaceSingleMatch(with: replacementText)
    }

    func contentFindBarDidRequestReplaceAll(_ replacementText: String) {
        replaceAllMatches(with: replacementText)
    }
}

// MARK: - Content Search

extension PreviewContainerViewController {

    /// The currently active NSTextView, if any.
    private var activeTextView: NSTextView? {
        switch currentMode {
        case .preview where useCodePreview:
            return codePreview.previewTextView
        case .editor:
            return editor.editorTextView
        default:
            return nil
        }
    }

    /// Re-applies the current search query to the active content view.
    private func reapplySearch() {
        let query = contentFindBar.searchText
        guard !query.isEmpty else { return }
        performContentSearch(query)
    }

    /// Searches the active content view for the given query.
    /// Routes to mmap search when the code preview is in mmap mode.
    private func performContentSearch(_ query: String) {
        clearSearchHighlights()

        guard !query.isEmpty else {
            contentFindBar.updateCounter(current: 0, total: 0)
            return
        }

        // mmap mode: search the mapped file bytes directly
        if currentMode == .preview, useCodePreview, codePreview.isMmapMode {
            Task { await searchInMmapFile(for: query) }
            return
        }

        if let textView = activeTextView {
            searchInTextView(textView, for: query)
        } else if currentMode == .preview && !useCodePreview {
            Task { await searchInWebView(for: query) }
        } else {
            contentFindBar.updateCounter(current: 0, total: 0)
        }
    }

    // MARK: NSTextView Search

    private static let matchHighlightColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.0, alpha: 0.25)
    private static let currentMatchColor = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.5)

    private func searchInTextView(_ textView: NSTextView, for query: String) {
        let text = textView.string as NSString
        let isRegex = contentFindBar.isRegexEnabled
        let caseSensitive = contentFindBar.isCaseSensitive
        let wholeWord = contentFindBar.isWholeWord

        var ranges: [NSRange] = []

        // When regex or whole-word is active, use NSRegularExpression for unified matching.
        // Otherwise, fall back to the faster NSString.range(of:) scan.
        if isRegex || wholeWord {
            do {
                let pattern: String
                if isRegex {
                    // Wrap user-provided regex in word boundaries if whole-word is also on
                    pattern = wholeWord ? "\\b(?:\(query))\\b" : query
                } else {
                    // Plain text + whole word — escape the query and wrap in \b
                    pattern = "\\b\(NSRegularExpression.escapedPattern(for: query))\\b"
                }
                var options: NSRegularExpression.Options = []
                if !caseSensitive { options.insert(.caseInsensitive) }
                let regex = try NSRegularExpression(pattern: pattern, options: options)
                let fullRange = NSRange(location: 0, length: text.length)
                ranges = regex.matches(in: text as String, range: fullRange).map(\.range)
            } catch {
                // Invalid regex — show error in counter, no crash
                contentFindBar.showError("Invalid regex")
                searchMatchRanges = []
                isSearchingWebView = false
                return
            }
        } else {
            // Plain substring search — optionally case-insensitive
            var options: NSString.CompareOptions = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            var searchRange = NSRange(location: 0, length: text.length)

            while searchRange.location < text.length {
                let range = text.range(of: query, options: options, range: searchRange)
                if range.location == NSNotFound { break }
                ranges.append(range)
                searchRange.location = range.location + range.length
                searchRange.length = text.length - searchRange.location
            }
        }

        searchMatchRanges = ranges
        isSearchingWebView = false

        guard !ranges.isEmpty else {
            contentFindBar.updateCounter(current: 0, total: 0)
            return
        }

        currentSearchMatchIndex = 0
        highlightAllMatches(in: textView)
        highlightCurrentMatch(in: textView)
        scrollToCurrentMatch(in: textView)
        contentFindBar.updateCounter(current: 1, total: ranges.count)
    }

    private func highlightAllMatches(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        for range in searchMatchRanges {
            layoutManager.addTemporaryAttribute(
                .backgroundColor, value: Self.matchHighlightColor, forCharacterRange: range
            )
        }
    }

    private func highlightCurrentMatch(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              searchMatchRanges.indices.contains(currentSearchMatchIndex) else { return }
        let range = searchMatchRanges[currentSearchMatchIndex]
        layoutManager.addTemporaryAttribute(
            .backgroundColor, value: Self.currentMatchColor, forCharacterRange: range
        )
    }

    private func scrollToCurrentMatch(in textView: NSTextView) {
        guard searchMatchRanges.indices.contains(currentSearchMatchIndex) else { return }
        let range = searchMatchRanges[currentSearchMatchIndex]
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    private func clearSearchHighlights() {
        // Clear NSTextView highlights from both editor and code preview
        clearTextViewHighlights(editor.editorTextView)
        clearTextViewHighlights(codePreview.previewTextView)
        searchMatchRanges = []
        currentSearchMatchIndex = 0

        // Clear WKWebView highlights
        if isSearchingWebView {
            markdownPreview.clearSearchHighlights()
            isSearchingWebView = false
            webViewMatchCount = 0
            webViewCurrentMatchIndex = 0
        }

        // Clear mmap search state
        if isSearchingMmap {
            isSearchingMmap = false
            mmapSearchMatches = []
            mmapCurrentMatchIndex = 0
        }
    }

    private func clearTextViewHighlights(_ textView: NSTextView?) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }

    // MARK: mmap Search

    /// Searches the memory-mapped file via LargeFileReader.searchAll.
    /// Results are byte offsets — navigation scrolls the code preview to the matching line.
    private func searchInMmapFile(for query: String) async {
        guard let reader = codePreview.largeFileReader else { return }

        isSearchingMmap = true
        let matches = await reader.searchAll(
            query: query,
            caseSensitive: contentFindBar.isCaseSensitive
        )
        mmapSearchMatches = matches
        mmapCurrentMatchIndex = 0

        guard !matches.isEmpty else {
            contentFindBar.updateCounter(current: 0, total: 0)
            return
        }

        contentFindBar.updateCounter(current: 1, total: matches.count)
        await navigateToMmapMatch(at: 0)
    }

    /// Scrolls the code preview to show the match at the given index and highlights it.
    private func navigateToMmapMatch(at index: Int) async {
        guard mmapSearchMatches.indices.contains(index),
              let reader = codePreview.largeFileReader else { return }

        let match = mmapSearchMatches[index]
        let line = await reader.lineNumber(forByteOffset: match.byteOffset)

        // Scroll the mmap view to the matching line
        codePreview.scrollToLine(line)

        // Try to highlight the match in the visible text view
        if let textView = codePreview.previewTextView {
            // Clear previous highlights
            clearTextViewHighlights(textView)

            // Calculate NSRange within the current window
            let windowStart = max(0, line - 100)
            if let nsRange = await reader.nsRange(
                forByteOffset: match.byteOffset,
                length: match.length,
                inLineWindow: windowStart,
                windowLineCount: 500
            ) {
                textView.layoutManager?.addTemporaryAttribute(
                    .backgroundColor, value: Self.currentMatchColor, forCharacterRange: nsRange
                )
                textView.scrollRangeToVisible(nsRange)
                textView.showFindIndicator(for: nsRange)
            }
        }
    }

    // MARK: WKWebView Search

    private func searchInWebView(for query: String) async {
        isSearchingWebView = true
        let count = await markdownPreview.searchContent(
            query,
            isRegex: contentFindBar.isRegexEnabled,
            caseSensitive: contentFindBar.isCaseSensitive,
            wholeWord: contentFindBar.isWholeWord
        )

        // -1 signals invalid regex from the JS side
        if count == -1 {
            contentFindBar.showError("Invalid regex")
            webViewMatchCount = 0
            webViewCurrentMatchIndex = 0
            return
        }

        webViewMatchCount = count
        webViewCurrentMatchIndex = 0

        if count > 0 {
            markdownPreview.navigateToSearchMatch(at: 0)
            contentFindBar.updateCounter(current: 1, total: count)
        } else {
            contentFindBar.updateCounter(current: 0, total: 0)
        }
    }

    // MARK: Navigation

    private func navigateToNextMatch() {
        // mmap search navigation
        if isSearchingMmap {
            guard !mmapSearchMatches.isEmpty else { return }
            mmapCurrentMatchIndex = (mmapCurrentMatchIndex + 1) % mmapSearchMatches.count
            contentFindBar.updateCounter(
                current: mmapCurrentMatchIndex + 1, total: mmapSearchMatches.count
            )
            Task { await navigateToMmapMatch(at: mmapCurrentMatchIndex) }
            return
        }

        if isSearchingWebView {
            guard webViewMatchCount > 0 else { return }
            webViewCurrentMatchIndex = (webViewCurrentMatchIndex + 1) % webViewMatchCount
            markdownPreview.navigateToSearchMatch(at: webViewCurrentMatchIndex)
            contentFindBar.updateCounter(
                current: webViewCurrentMatchIndex + 1, total: webViewMatchCount
            )
            return
        }

        guard let textView = activeTextView, !searchMatchRanges.isEmpty else { return }

        // Restore previous match to standard highlight
        let oldRange = searchMatchRanges[currentSearchMatchIndex]
        textView.layoutManager?.addTemporaryAttribute(
            .backgroundColor, value: Self.matchHighlightColor, forCharacterRange: oldRange
        )

        // Advance to next match
        currentSearchMatchIndex = (currentSearchMatchIndex + 1) % searchMatchRanges.count
        highlightCurrentMatch(in: textView)
        scrollToCurrentMatch(in: textView)
        contentFindBar.updateCounter(
            current: currentSearchMatchIndex + 1, total: searchMatchRanges.count
        )
    }

    private func navigateToPreviousMatch() {
        // mmap search navigation
        if isSearchingMmap {
            guard !mmapSearchMatches.isEmpty else { return }
            mmapCurrentMatchIndex = (mmapCurrentMatchIndex - 1 + mmapSearchMatches.count) % mmapSearchMatches.count
            contentFindBar.updateCounter(
                current: mmapCurrentMatchIndex + 1, total: mmapSearchMatches.count
            )
            Task { await navigateToMmapMatch(at: mmapCurrentMatchIndex) }
            return
        }

        if isSearchingWebView {
            guard webViewMatchCount > 0 else { return }
            webViewCurrentMatchIndex = (webViewCurrentMatchIndex - 1 + webViewMatchCount) % webViewMatchCount
            markdownPreview.navigateToSearchMatch(at: webViewCurrentMatchIndex)
            contentFindBar.updateCounter(
                current: webViewCurrentMatchIndex + 1, total: webViewMatchCount
            )
            return
        }

        guard let textView = activeTextView, !searchMatchRanges.isEmpty else { return }

        // Restore previous match to standard highlight
        let oldRange = searchMatchRanges[currentSearchMatchIndex]
        textView.layoutManager?.addTemporaryAttribute(
            .backgroundColor, value: Self.matchHighlightColor, forCharacterRange: oldRange
        )

        // Move to previous match
        currentSearchMatchIndex = (currentSearchMatchIndex - 1 + searchMatchRanges.count) % searchMatchRanges.count
        highlightCurrentMatch(in: textView)
        scrollToCurrentMatch(in: textView)
        contentFindBar.updateCounter(
            current: currentSearchMatchIndex + 1, total: searchMatchRanges.count
        )
    }

    // MARK: Replace

    /// Replaces the current highlighted match and advances to the next one.
    /// Only operates when in editor mode with active search matches.
    private func replaceSingleMatch(with replacement: String) {
        guard currentMode == .editor,
              let textView = editor.editorTextView,
              searchMatchRanges.indices.contains(currentSearchMatchIndex) else { return }

        let range = searchMatchRanges[currentSearchMatchIndex]

        // Use insertText to integrate with the undo manager
        textView.setSelectedRange(range)
        textView.insertText(replacement, replacementRange: range)

        // Re-highlight after replacement
        editor.rehighlight()

        // Refresh search to rebuild match ranges with the new text
        let query = contentFindBar.searchText
        performContentSearch(query)

        // Clamp the index so we land on the next match after the replaced one
        if !searchMatchRanges.isEmpty {
            currentSearchMatchIndex = min(currentSearchMatchIndex, searchMatchRanges.count - 1)
            highlightCurrentMatch(in: textView)
            scrollToCurrentMatch(in: textView)
            contentFindBar.updateCounter(
                current: currentSearchMatchIndex + 1, total: searchMatchRanges.count
            )
        }
    }

    /// Replaces all matches with the given replacement text in a single undoable action.
    /// Iterates in reverse to preserve earlier match ranges as later ones shift.
    private func replaceAllMatches(with replacement: String) {
        guard currentMode == .editor,
              let textView = editor.editorTextView,
              !searchMatchRanges.isEmpty else { return }

        // Group all replacements as a single undoable action
        textView.undoManager?.beginUndoGrouping()

        // Replace in reverse order so earlier ranges remain valid
        for range in searchMatchRanges.reversed() {
            textView.insertText(replacement, replacementRange: range)
        }

        textView.undoManager?.endUndoGrouping()

        // Re-highlight and clear search state
        editor.rehighlight()
        let query = contentFindBar.searchText
        performContentSearch(query)
    }
}

// MARK: - EditorStatusBarDelegate

extension PreviewContainerViewController: EditorStatusBarDelegate {

    func statusBarDidRequestEncodingMenu(from button: NSView) {
        let menu = EditorStatusBarMenus.encodingMenu(
            current: editor.fileEncoding,
            reopenTarget: self,
            reopenAction: #selector(reopenWithEncodingMenuAction(_:)),
            saveTarget: self,
            saveAction: #selector(saveWithEncodingMenuAction(_:))
        )
        showMenu(menu, from: button)
    }

    func statusBarDidRequestLineEndingMenu(from button: NSView) {
        let menu = EditorStatusBarMenus.lineEndingMenu(
            current: editor.lineEndings,
            target: self,
            action: #selector(lineEndingMenuAction(_:))
        )
        showMenu(menu, from: button)
    }

    func statusBarDidRequestIndentMenu(from button: NSView) {
        let menu = EditorStatusBarMenus.indentMenu(
            current: editor.indentStyle,
            indentTarget: self,
            indentAction: #selector(indentStyleMenuAction(_:)),
            convertTarget: self,
            convertAction: #selector(convertIndentMenuAction(_:))
        )
        showMenu(menu, from: button)
    }

    func statusBarDidToggleWordWrap() {
        editor.toggleWordWrap()
        editorStatusBar.updateWordWrap(editor.wordWrapEnabled)
    }

    /// Positions a menu below the given button, aligned to the button's leading edge.
    private func showMenu(_ menu: NSMenu, from button: NSView) {
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    // MARK: Menu Actions

    @objc private func reopenWithEncodingMenuAction(_ sender: NSMenuItem) {
        let encoding = String.Encoding(rawValue: UInt(sender.tag))
        editor.reopenWithEncoding(encoding)
        hasUnsavedChanges = false
        updateButtonVisibility()
    }

    @objc private func saveWithEncodingMenuAction(_ sender: NSMenuItem) {
        let encoding = String.Encoding(rawValue: UInt(sender.tag))
        editor.setEncodingForSave(encoding)
        if !hasUnsavedChanges {
            hasUnsavedChanges = true
            updateButtonVisibility()
        }
    }

    @objc private func lineEndingMenuAction(_ sender: NSMenuItem) {
        let ending = EditorStatusBarMenus.lineEnding(fromTag: sender.tag)
        editor.convertLineEndings(to: ending)
        if !hasUnsavedChanges {
            hasUnsavedChanges = true
            updateButtonVisibility()
        }
    }

    @objc private func indentStyleMenuAction(_ sender: NSMenuItem) {
        let style = EditorStatusBarMenus.indentStyle(fromTag: sender.tag)
        editor.setIndentStyle(style)
    }

    @objc private func convertIndentMenuAction(_ sender: NSMenuItem) {
        let style = EditorStatusBarMenus.indentStyle(fromTag: sender.tag)
        editor.convertIndentation(to: style)
        if !hasUnsavedChanges {
            hasUnsavedChanges = true
            updateButtonVisibility()
        }
    }
}

// MARK: - PreviewZoomControlsDelegate

extension PreviewContainerViewController: PreviewZoomControlsDelegate {

    func zoomControlsDidZoomIn() {
        markdownPreview.zoomIn()
    }

    func zoomControlsDidZoomOut() {
        markdownPreview.zoomOut()
    }

    func zoomControlsDidResetZoom() {
        markdownPreview.resetZoom()
    }

    func zoomControlsDidZoomToActualSize() {
        markdownPreview.zoomToActualSize()
    }
}

// MARK: - Pointer Cursor Stack View

/// NSStackView subclass that shows a pointing hand cursor over its arranged button subviews.
private final class PointerCursorStackView: NSStackView {
    override func resetCursorRects() {
        super.resetCursorRects()
        for view in arrangedSubviews where view is NSButton && !view.isHidden {
            view.discardCursorRects()
            let rect = convert(view.bounds, from: view)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }
}
