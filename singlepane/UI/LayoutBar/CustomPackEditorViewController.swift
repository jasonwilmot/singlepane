// CustomPackEditorViewController.swift
// Sheet-presented editor for creating and editing custom audio packs.
// Shows a name field and 6 hook-event sections, each with file list,
// drag-and-drop zone, and add/remove controls.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class CustomPackEditorViewController: NSViewController {

    // MARK: - Mode

    /// The pack name being edited, or nil when creating a new pack.
    private let editingPackName: String?

    /// Whether we are editing an existing pack vs. creating a new one.
    private var isEditMode: Bool { editingPackName != nil }

    /// Called when the sheet is dismissed (save, delete, or cancel) so the
    /// caller can refresh the voice menu.
    var onDismiss: (() -> Void)?

    // MARK: - UI Elements

    private let scrollView = NSScrollView()
    private let contentView = FlippedView()
    private let nameField = NSTextField()
    private var sectionViews: [EventSectionView] = []
    private let saveButton = NSButton()
    private let cancelButton = NSButton()
    private var deleteButton: NSButton?

    // MARK: - State

    /// Staged files per event. Key is the event name, value is an array of source URLs
    /// (already-copied files for existing packs, or pending source URLs for new imports).
    private var stagedFiles: [String: [URL]] = [:]

    /// The working pack directory name (for existing packs, this is the current name on disk).
    private var workingPackName: String?

    // MARK: - Init

    init(editingPackName: String?) {
        self.editingPackName = editingPackName
        self.workingPackName = editingPackName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateExistingData()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.layoutSubtreeIfNeeded()
        scrollView.documentView?.scroll(.zero)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        // Name field at top
        let nameLabel = NSTextField(labelWithString: "Pack Name")
        nameLabel.font = FontManager.shared.activeFont.withSize(11)
        nameLabel.textColor = theme.chromeTextSecondary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        nameField.font = FontManager.shared.activeFont.withSize(13)
        nameField.textColor = theme.chromeText
        nameField.backgroundColor = theme.chromeBackground
        nameField.placeholderString = "My Custom Pack"
        nameField.isBordered = true
        nameField.bezelStyle = .roundedBezel
        nameField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameField)

        // Scroll view for event sections
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        // Build event sections
        var previousAnchor = contentView.topAnchor
        for event in VoicePack.hookEvents {
            let section = EventSectionView(event: event, delegate: self)
            section.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(section)
            sectionViews.append(section)

            NSLayoutConstraint.activate([
                section.topAnchor.constraint(equalTo: previousAnchor, constant: 16),
                section.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                section.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            previousAnchor = section.bottomAnchor
        }

        // Pin the bottom of the content view to the last section
        contentView.bottomAnchor.constraint(equalTo: previousAnchor, constant: 12).isActive = true

        // Bottom button bar
        let buttonFont = FontManager.shared.activeFont.withSize(13)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.font = buttonFont
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        saveButton.title = isEditMode ? "Save" : "Create"
        saveButton.bezelStyle = .rounded
        saveButton.font = buttonFont
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        var buttonConstraints = [
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ]

        // Delete button — only in edit mode
        if isEditMode {
            let del = NSButton()
            del.title = "Delete Pack"
            del.bezelStyle = .rounded
            del.font = buttonFont
            del.contentTintColor = .systemRed
            del.target = self
            del.action = #selector(deleteClicked)
            del.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(del)
            deleteButton = del

            buttonConstraints.append(contentsOf: [
                del.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                del.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            ])
        }

        NSLayoutConstraint.activate(buttonConstraints + [
            nameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),

            // Content view width matches scroll view
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    // MARK: - Populate Existing Data

    /// Loads files from an existing custom pack into the staged state and UI.
    private func populateExistingData() {
        guard let packName = editingPackName else { return }
        nameField.stringValue = VoicePack(directoryName: packName, storageURL: AudioManager.customPacksDirectoryURL.appendingPathComponent(packName)).displayName

        // Use the raw directory name for the name field so renames work correctly
        nameField.stringValue = packName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        for (index, event) in VoicePack.hookEvents.enumerated() {
            let files = AudioManager.shared.filesForEvent(event, in: packName)
            stagedFiles[event] = files
            sectionViews[index].reloadFiles(files)
        }
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        dismissSheet()
    }

    @objc private func saveClicked() {
        let rawName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            nameField.becomeFirstResponder()
            return
        }

        // Sanitize the name for use as a directory name
        let dirName = rawName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()

        let manager = AudioManager.shared

        if isEditMode, let oldName = workingPackName, oldName != dirName {
            // Rename if the name changed
            manager.renameCustomPack(oldName, to: dirName)
        }

        if !isEditMode {
            // Create the new pack directory structure
            manager.createCustomPack(named: dirName)
        }

        // Sync files: for each event, copy any new files and remove deleted ones
        let currentName = dirName
        for event in VoicePack.hookEvents {
            let stagedURLs = stagedFiles[event] ?? []
            let existingFiles = manager.filesForEvent(event, in: currentName)
            let existingNames = Set(existingFiles.map(\.lastPathComponent))
            let stagedNames = Set(stagedURLs.map(\.lastPathComponent))

            // Remove files that were deleted from the UI
            for existing in existingFiles where !stagedNames.contains(existing.lastPathComponent) {
                manager.removeFile(existing.lastPathComponent, from: currentName, event: event)
            }

            // Copy files that are new (not already in the pack directory)
            for staged in stagedURLs where !existingNames.contains(staged.lastPathComponent) {
                manager.addFile(to: currentName, event: event, from: staged)
            }
        }

        // Select the pack and refresh
        manager.refreshVoicePacks()
        manager.selectVoicePack(named: currentName)
        dismissSheet()
    }

    @objc private func deleteClicked() {
        guard let packName = workingPackName else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Custom Pack?"
        alert.informativeText = "This will permanently remove all audio files in this pack."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: view.window!) { response in
            guard response == .alertFirstButtonReturn else { return }
            AudioManager.shared.deleteCustomPack(packName)
            self.dismissSheet()
        }
    }

    private func dismissSheet() {
        guard let sheetWindow = view.window,
              let parentWindow = sheetWindow.sheetParent else { return }
        parentWindow.endSheet(sheetWindow)
        onDismiss?()
    }
}

// MARK: - EventSectionDelegate

/// Delegate for event section interactions (add files, remove file).
@MainActor
protocol EventSectionDelegate: AnyObject {
    func eventSection(_ section: EventSectionView, didAddFiles urls: [URL], forEvent event: String)
    func eventSection(_ section: EventSectionView, didRemoveFileAt index: Int, forEvent event: String)
    func eventSection(_ section: EventSectionView, requestAddFilesForEvent event: String)
}

extension CustomPackEditorViewController: EventSectionDelegate {

    func eventSection(_ section: EventSectionView, didAddFiles urls: [URL], forEvent event: String) {
        var current = stagedFiles[event] ?? []
        current.append(contentsOf: urls)
        stagedFiles[event] = current
        if let index = VoicePack.hookEvents.firstIndex(of: event) {
            sectionViews[index].reloadFiles(current)
        }
    }

    func eventSection(_ section: EventSectionView, didRemoveFileAt index: Int, forEvent event: String) {
        var current = stagedFiles[event] ?? []
        guard index < current.count else { return }
        current.remove(at: index)
        stagedFiles[event] = current
        if let sectionIndex = VoicePack.hookEvents.firstIndex(of: event) {
            sectionViews[sectionIndex].reloadFiles(current)
        }
    }

    func eventSection(_ section: EventSectionView, requestAddFilesForEvent event: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.wav,
        ]
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK else { return }
            self?.eventSection(section, didAddFiles: panel.urls, forEvent: event)
        }
    }
}

// MARK: - EventSectionView

/// A collapsible section for one hook event (e.g., "hello").
/// Contains a header, file list with per-file delete buttons, an "Add Files" button,
/// and a drag-and-drop target zone.
@MainActor
final class EventSectionView: NSView {

    // MARK: - Properties

    let event: String
    private weak var delegate: EventSectionDelegate?
    private let fileStackView = NSStackView()
    private let dropZone: AudioDropZoneView
    private var fileRows: [FileRowView] = []

    /// Human-readable labels for each hook event.
    private static let eventLabels: [String: String] = [
        "hello": "Start",
        "prompt": "Prompt",
        "agent": "Agent",
        "stop": "Stop",
        "end": "End",
        "notification": "Notification",
    ]

    /// Helper descriptions for each hook event.
    private static let eventDescriptions: [String: String] = [
        "hello": "When a Claude Code session begins or resumes",
        "prompt": "When you submit a prompt, before Claude processes it",
        "agent": "When a subagent is spawned",
        "stop": "When Claude finishes responding",
        "end": "When a session terminates",
        "notification": "When Claude Code needs your input",
    ]

    // MARK: - Init

    init(event: String, delegate: EventSectionDelegate) {
        self.event = event
        self.delegate = delegate
        self.dropZone = AudioDropZoneView()
        super.init(frame: .zero)
        setupUI()
        dropZone.onDrop = { [weak self] urls in
            guard let self else { return }
            delegate.eventSection(self, didAddFiles: urls, forEvent: event)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme

        // Rounded border for the entire section
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = theme.chromeTextSecondary.withAlphaComponent(0.25).cgColor

        let inset: CGFloat = 12

        // Event name + helper description on the same line: "Start — When a Claude Code session begins or resumes"
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 0
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        let nameLabel = NSTextField(labelWithString: Self.eventLabels[event] ?? event.capitalized)
        let baseFont = FontManager.shared.activeFont.withSize(14)
        nameLabel.font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        nameLabel.textColor = theme.paletteColor(at: 4)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let descText = " — \(Self.eventDescriptions[event] ?? "")"
        let descLabel = NSTextField(labelWithString: descText)
        descLabel.font = FontManager.shared.activeFont.withSize(11)
        descLabel.textColor = theme.chromeTextSecondary
        descLabel.lineBreakMode = .byTruncatingTail

        headerStack.addArrangedSubview(nameLabel)
        headerStack.addArrangedSubview(descLabel)

        // File list stack (vertical)
        fileStackView.orientation = .vertical
        fileStackView.alignment = .leading
        fileStackView.spacing = 2
        fileStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fileStackView)

        // Drop zone (also clickable to open file picker)
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.eventSection(self, requestAddFilesForEvent: self.event)
        }
        addSubview(dropZone)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            fileStackView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            fileStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            fileStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            dropZone.topAnchor.constraint(equalTo: fileStackView.bottomAnchor, constant: 4),
            dropZone.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            dropZone.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            dropZone.heightAnchor.constraint(equalToConstant: 36),
            dropZone.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    // MARK: - Reload

    /// Updates the file list UI to match the given URLs.
    func reloadFiles(_ files: [URL]) {
        // Remove old rows
        for row in fileRows {
            fileStackView.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        fileRows.removeAll()

        // Add new rows
        for (index, fileURL) in files.enumerated() {
            let row = FileRowView(fileName: fileURL.lastPathComponent, index: index) { [weak self] idx in
                guard let self else { return }
                self.delegate?.eventSection(self, didRemoveFileAt: idx, forEvent: self.event)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            fileStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: fileStackView.widthAnchor).isActive = true
            fileRows.append(row)
        }
    }
}

// MARK: - FileRowView

/// A single row showing a file name and a delete button.
@MainActor
private final class FileRowView: NSView {

    init(fileName: String, index: Int, onDelete: @escaping (Int) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 22))

        let theme = ThemeManager.shared.activeTheme

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio file")
        icon.contentTintColor = theme.chromeTextSecondary
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let label = NSTextField(labelWithString: fileName)
        label.font = FontManager.shared.activeFont.withSize(11)
        label.textColor = theme.paletteColor(at: 5)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let deleteBtn = NSButton()
        deleteBtn.bezelStyle = .inline
        deleteBtn.isBordered = false
        deleteBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove file")?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        deleteBtn.imagePosition = .imageOnly
        deleteBtn.contentTintColor = theme.chromeTextSecondary
        deleteBtn.tag = index
        deleteBtn.target = self
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteBtn)

        // Store the callback via objc target/action pattern with a closure wrapper
        self.deleteAction = { onDelete(index) }
        deleteBtn.action = #selector(deleteClicked)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: deleteBtn.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            deleteBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 18),
            deleteBtn.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var deleteAction: (() -> Void)?

    @objc private func deleteClicked() {
        deleteAction?()
    }
}

// MARK: - AudioDropZoneView

/// A dashed-border drop zone that accepts mp3 and wav files via drag and drop.
@MainActor
final class AudioDropZoneView: NSView {

    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    private var isDragOver = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ThemeManager.shared.activeTheme
        let borderColor = isDragOver
            ? theme.chromeText.withAlphaComponent(0.4)
            : theme.chromeTextSecondary.withAlphaComponent(0.3)

        // Dashed border
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        let pattern: [CGFloat] = [4, 3]
        path.setLineDash(pattern, count: 2, phase: 0)
        path.lineWidth = 1
        borderColor.setStroke()
        path.stroke()

        // Center text
        let text = "Drop or click to add audio files" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: FontManager.shared.activeFont.withSize(10),
            .foregroundColor: theme.chromeTextSecondary,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)
    }

    // MARK: - Click to Add

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasValidAudioFiles(sender) else { return [] }
        isDragOver = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragOver = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDragOver = false
        needsDisplay = true

        let urls = extractAudioURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    /// Checks whether the drag pasteboard contains at least one valid audio file.
    private func hasValidAudioFiles(_ info: NSDraggingInfo) -> Bool {
        guard let items = info.draggingPasteboard.pasteboardItems else { return false }
        return items.contains { item in
            guard let urlString = item.string(forType: .fileURL),
                  let url = URL(string: urlString) else { return false }
            return VoicePack.audioExtensions.contains(url.pathExtension.lowercased())
        }
    }

    /// Extracts audio file URLs from the drag pasteboard.
    private func extractAudioURLs(from info: NSDraggingInfo) -> [URL] {
        guard let items = info.draggingPasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            guard let urlString = item.string(forType: .fileURL),
                  let url = URL(string: urlString),
                  VoicePack.audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }
    }
}

// MARK: - FlippedView

/// An NSView subclass with a flipped coordinate system so (0,0) is top-left.
/// Used as the scroll view's document view so scrolling to .zero shows the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
