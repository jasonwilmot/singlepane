// BreadcrumbEditField.swift
// Text field overlay for breadcrumb edit mode.
// Provides path-aware autocomplete: as the user types, matching subdirectory names
// appear in a dropdown. Tab accepts the top suggestion, Enter navigates, Escape cancels.

import AppKit

/// Actions emitted by the edit field to its owner (BreadcrumbBarView).
@MainActor
protocol BreadcrumbEditFieldDelegate: AnyObject {
    /// User pressed Enter — navigate to the confirmed path.
    func breadcrumbEditFieldDidConfirm(path: String)
    /// User pressed Escape or clicked outside — cancel edit mode.
    func breadcrumbEditFieldDidCancel()
    /// Request autocomplete suggestions for a directory prefix.
    func breadcrumbEditFieldRequestAutocomplete(
        directory: URL,
        prefix: String,
        completion: @escaping ([String]) -> Void
    )
    /// FAYT: filter text changed while in filter mode (text after trailing `/`).
    func breadcrumbEditFieldDidChangeFilter(_ filterText: String)
    /// FAYT: user pressed Enter while in filter mode — lock the filter in.
    func breadcrumbEditFieldDidConfirmFilter(_ filterText: String)
}

@MainActor
final class BreadcrumbEditField: NSView, NSTextFieldDelegate {

    // MARK: - Properties

    weak var editDelegate: BreadcrumbEditFieldDelegate?

    /// The current directory URL, set on activation.
    /// Used to detect filter mode: when the path portion matches this URL,
    /// text after the trailing `/` is treated as a FAYT filter query.
    private var currentDirectoryURL: URL?

    private let textField = NSTextField()
    private var autocompletePopup: NSWindow?
    private var autocompleteSuggestions: [String] = []
    private var autocompleteTableView: NSTableView?

    /// Debounce timer for autocomplete requests.
    private var autocompleteTimer: Timer?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTextField()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupTextField() {
        textField.delegate = self
        textField.font = FontManager.shared.activeFont.withSize(12)
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Activation

    /// Show the text field pre-filled with the current path and select all text.
    /// Used for standard path-editing mode (clicking empty breadcrumb space).
    func activate(with path: String) {
        currentDirectoryURL = URL(fileURLWithPath: path)
        textField.stringValue = path
        textField.isHidden = false
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    /// Activate in FAYT filter mode — path shown with trailing `/`, cursor at end.
    /// Optionally appends initial characters (from just-start-typing activation).
    func activateForFilter(directoryPath: String, initialText: String = "") {
        currentDirectoryURL = URL(fileURLWithPath: directoryPath)
        let filterPath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        textField.stringValue = filterPath + initialText
        textField.isHidden = false
        window?.makeFirstResponder(textField)

        // Place cursor at end (don't select all — user is typing a filter)
        if let editor = textField.currentEditor() {
            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
        }

        // If initial text was provided, immediately emit a filter change
        if !initialText.isEmpty {
            editDelegate?.breadcrumbEditFieldDidChangeFilter(initialText)
        }
    }

    /// Hide the text field and dismiss any autocomplete popup.
    func deactivate() {
        dismissAutocomplete()
        autocompleteTimer?.invalidate()
        autocompleteTimer = nil
        textField.isHidden = true
        // Return focus to the window's content view
        window?.makeFirstResponder(window?.contentView)
    }

    // MARK: - Filter Mode Detection

    /// Returns the filter text if currently in filter mode, or nil if in navigate mode.
    /// Filter mode is active when the path portion (before trailing content) matches
    /// the current directory. The text after the last `/` of the current directory path
    /// is the filter query.
    private func currentFilterText() -> String? {
        guard let dirURL = currentDirectoryURL else { return nil }

        let fullText = textField.stringValue
        let dirPath = dirURL.path
        let dirPrefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"

        // If the text starts with the current directory path + "/", everything after is the filter
        guard fullText.hasPrefix(dirPrefix) else { return nil }

        return String(fullText.dropFirst(dirPrefix.count))
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        // Check if we're in filter mode (path portion matches current directory)
        if let filterText = currentFilterText() {
            // FAYT mode — emit filter changes immediately (no debounce for local filtering)
            dismissAutocomplete()
            editDelegate?.breadcrumbEditFieldDidChangeFilter(filterText)
            return
        }

        // Navigate mode — debounce autocomplete requests
        autocompleteTimer?.invalidate()
        autocompleteTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.requestAutocomplete()
            }
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if let filterText = currentFilterText() {
                // Filter mode — lock in the filter
                editDelegate?.breadcrumbEditFieldDidConfirmFilter(filterText)
            } else {
                // Navigate mode — confirm path navigation
                editDelegate?.breadcrumbEditFieldDidConfirm(path: textField.stringValue)
            }
            return true

        case #selector(NSResponder.cancelOperation(_:)):
            // Escape — cancel edit mode (clears filter if active)
            editDelegate?.breadcrumbEditFieldDidCancel()
            return true

        case #selector(NSResponder.insertTab(_:)):
            // Tab — accept top autocomplete suggestion (navigate mode only)
            if currentFilterText() == nil {
                acceptTopSuggestion()
            }
            return true

        case #selector(NSResponder.moveDown(_:)):
            // Down arrow — select next item in autocomplete
            selectNextSuggestion()
            return true

        case #selector(NSResponder.moveUp(_:)):
            // Up arrow — select previous item in autocomplete
            selectPreviousSuggestion()
            return true

        default:
            return false
        }
    }

    // MARK: - Autocomplete

    /// Parses the current text field value to determine directory and prefix,
    /// then requests matching subdirectory names.
    private func requestAutocomplete() {
        let fullPath = textField.stringValue
        guard !fullPath.isEmpty else {
            dismissAutocomplete()
            return
        }

        let url = URL(fileURLWithPath: fullPath)
        let directory: URL
        let prefix: String

        if fullPath.hasSuffix("/") {
            // User typed a full directory path — show all children
            directory = url
            prefix = ""
        } else {
            // User is typing a partial name — match against siblings
            directory = url.deletingLastPathComponent()
            prefix = url.lastPathComponent
        }

        editDelegate?.breadcrumbEditFieldRequestAutocomplete(
            directory: directory,
            prefix: prefix
        ) { [weak self] suggestions in
            guard let self else { return }
            self.autocompleteSuggestions = suggestions
            if suggestions.isEmpty {
                self.dismissAutocomplete()
            } else {
                self.showAutocompletePopup(suggestions: suggestions)
            }
        }
    }

    /// Accept the currently selected (or first) autocomplete suggestion.
    private func acceptTopSuggestion() {
        let selectedIndex = autocompleteTableView?.selectedRow ?? 0
        guard selectedIndex >= 0, selectedIndex < autocompleteSuggestions.count else { return }

        let suggestion = autocompleteSuggestions[selectedIndex]
        let fullPath = textField.stringValue

        // Build the completed path
        let basePath: String
        if fullPath.hasSuffix("/") {
            basePath = fullPath
        } else {
            basePath = (fullPath as NSString).deletingLastPathComponent
            + (fullPath.contains("/") ? "/" : "")
        }

        textField.stringValue = basePath + suggestion + "/"
        dismissAutocomplete()

        // Trigger autocomplete again for the new deeper path
        requestAutocomplete()
    }

    private func selectNextSuggestion() {
        guard let table = autocompleteTableView else { return }
        let next = min(table.selectedRow + 1, autocompleteSuggestions.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func selectPreviousSuggestion() {
        guard let table = autocompleteTableView else { return }
        let prev = max(table.selectedRow - 1, 0)
        table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        table.scrollRowToVisible(prev)
    }

    // MARK: - Autocomplete Popup

    /// Shows or updates the autocomplete dropdown below the text field.
    private func showAutocompletePopup(suggestions: [String]) {
        if autocompletePopup == nil {
            createAutocompletePopup()
        }

        autocompleteTableView?.reloadData()

        // Select first row
        autocompleteTableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        // Position popup below the text field
        guard let parentWindow = window else { return }
        let fieldRect = textField.convert(textField.bounds, to: nil)
        let screenRect = parentWindow.convertToScreen(fieldRect)

        let rowCount = min(suggestions.count, 8)
        let popupHeight = CGFloat(rowCount) * 20 + 16
        let popupFrame = NSRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y - popupHeight,
            width: screenRect.width,
            height: popupHeight
        )

        autocompletePopup?.setFrame(popupFrame, display: true)
        if !(autocompletePopup?.isVisible ?? false) {
            parentWindow.addChildWindow(autocompletePopup!, ordered: .above)
            autocompletePopup?.orderFront(nil)
        }
    }

    /// Creates the autocomplete popup window with a table view.
    private func createAutocompletePopup() {
        let popup = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        popup.isOpaque = false
        popup.backgroundColor = NSColor.windowBackgroundColor
        popup.hasShadow = true
        popup.level = .popUpMenu

        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion"))
        column.title = ""
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(autocompleteDoubleClicked(_:))
        table.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        scrollView.frame = popup.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        popup.contentView?.addSubview(scrollView)

        autocompletePopup = popup
        autocompleteTableView = table
    }

    /// Dismisses and removes the autocomplete popup.
    private func dismissAutocomplete() {
        if let popup = autocompletePopup {
            popup.parent?.removeChildWindow(popup)
            popup.orderOut(nil)
        }
        autocompleteSuggestions = []
    }

    @objc private func autocompleteDoubleClicked(_ sender: Any) {
        acceptTopSuggestion()
    }
}

// MARK: - NSTableViewDataSource & Delegate (Autocomplete Popup)

extension BreadcrumbEditField: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        autocompleteSuggestions.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard row < autocompleteSuggestions.count else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("suggestion")
        let cellView: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = existing
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = FontManager.shared.activeFont.withSize(12)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(label)
            cellView.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        cellView.textField?.stringValue = autocompleteSuggestions[row]
        return cellView
    }
}
