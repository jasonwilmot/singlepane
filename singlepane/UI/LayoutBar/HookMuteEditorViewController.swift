// HookMuteEditorViewController.swift
// Sheet editor for global hook mute settings.
// Allows the user to mute or unmute individual hook events across all sound packs.

import AppKit

@MainActor
final class HookMuteEditorViewController: NSViewController {

    // MARK: - Properties

    private let closeButton = NSButton()

    /// Event labels matching CustomPackEditorViewController.
    private static let eventLabels: [String: String] = [
        "hello": "Start",
        "prompt": "Prompt",
        "agent": "Agent",
        "stop": "Stop",
        "end": "End",
        "notification": "Notification",
    ]

    /// Helper descriptions matching CustomPackEditorViewController.
    private static let eventDescriptions: [String: String] = [
        "hello": "When a Claude Code session begins or resumes",
        "prompt": "When you submit a prompt, before Claude processes it",
        "agent": "When a subagent is spawned",
        "stop": "When Claude finishes responding",
        "end": "When a session terminates",
        "notification": "When Claude Code needs your input",
    ]

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 0))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme
        let font = FontManager.shared.activeFont
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        let mutedHooks = AudioManager.shared.globalMutedHooks()

        // Title
        let titleLabel = NSTextField(labelWithString: "Sound Settings")
        let baseFont = font.withSize(16)
        titleLabel.font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        titleLabel.textColor = theme.paletteColor(at: 4)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Helper text
        let helperLabel = NSTextField(wrappingLabelWithString: "If using Claude Code, select which hooks you want to hear sounds for:")
        helperLabel.font = font.withSize(11)
        helperLabel.textColor = theme.chromeTextSecondary
        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(helperLabel)

        // Build rows for each hook event
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        for event in VoicePack.hookEvents {
            let row = createHookRow(
                event: event,
                isMuted: mutedHooks.contains(event),
                theme: theme,
                font: font
            )
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        // Close button
        closeButton.title = "Done"
        closeButton.bezelStyle = .rounded
        closeButton.font = font.withSize(13)
        closeButton.keyEquivalent = "\r"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            helperLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            helperLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            helperLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            stackView.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            closeButton.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Hook Row

    private func createHookRow(event: String, isMuted: Bool, theme: Theme, font: NSFont) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = theme.chromeTextSecondary.withAlphaComponent(0.25).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        // Speaker icon button — toggles mute state
        let speakerButton = NSButton()
        speakerButton.bezelStyle = .accessoryBarAction
        speakerButton.isBordered = false
        speakerButton.setButtonType(.toggle)
        speakerButton.state = isMuted ? .on : .off
        speakerButton.target = self
        speakerButton.action = #selector(speakerToggled(_:))
        speakerButton.tag = VoicePack.hookEvents.firstIndex(of: event) ?? 0
        speakerButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(speakerButton)
        applySpeakerAppearance(speakerButton, muted: isMuted, theme: theme)

        // Event name
        let nameLabel = NSTextField(labelWithString: Self.eventLabels[event] ?? event.capitalized)
        let boldFont = NSFontManager.shared.convert(font.withSize(13), toHaveTrait: .boldFontMask)
        nameLabel.font = boldFont
        nameLabel.textColor = theme.paletteColor(at: 4)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        // Description
        let descLabel = NSTextField(labelWithString: Self.eventDescriptions[event] ?? "")
        descLabel.font = font.withSize(10)
        descLabel.textColor = theme.chromeTextSecondary
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(descLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),

            speakerButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            speakerButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            speakerButton.widthAnchor.constraint(equalToConstant: 28),
            speakerButton.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: speakerButton.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        return container
    }

    /// Sets the speaker button icon and tint color based on mute state.
    private func applySpeakerAppearance(_ button: NSButton, muted: Bool, theme: Theme) {
        let symbolName = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let color = muted ? theme.hookRed : theme.hookGreen
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: muted ? "Muted" : "Enabled")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = color
    }

    // MARK: - Hooks JSON

    /// The hooks configuration JSON to add to ~/.claude/settings.json.
    /// UserPromptSubmit and Stop hooks read stdin JSON to extract prompt/response
    /// text and pass it URL-encoded as the &body= parameter for notifications.
    static let hooksJSON = """
    "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": "open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=hello\\""}]}],
        "SessionEnd": [{"hooks": [{"type": "command", "command": "open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=end\\""}]}],
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "BODY=$(cat | python3 -c 'import sys,json,urllib.parse;d=json.load(sys.stdin);print(urllib.parse.quote(d.get(\\"prompt\\",\\"\\")[:200]))' 2>/dev/null); open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=prompt&body=$BODY\\""}]}],
        "SubagentStart": [{"hooks": [{"type": "command", "command": "open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=agent\\""}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "BODY=$(cat | python3 -c 'import sys,json,urllib.parse;d=json.load(sys.stdin);print(urllib.parse.quote(d.get(\\"last_assistant_message\\",\\"\\")[:200]))' 2>/dev/null); open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=stop&body=$BODY\\""}]}],
        "Notification": [{"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "open -g \\"singlepane://hook?tab=$SP_TAB_ID&event=notification\\""}]}]
      }
    """

    /// Path to the Claude Code settings file.
    static let settingsPath = NSString("~/.claude/settings.json").expandingTildeInPath

    /// Shell command that reads stdin JSON, extracts a field, URL-encodes it, and opens the hook URL.
    private static func bodyExtractCommand(field: String, event: String) -> String {
        "BODY=$(cat | python3 -c 'import sys,json,urllib.parse;d=json.load(sys.stdin);print(urllib.parse.quote(d.get(\"\(field)\",\"\")[:200]))' 2>/dev/null); open -g \"singlepane://hook?tab=$SP_TAB_ID&event=\(event)&body=$BODY\""
    }

    /// Hooks config as a dictionary, for programmatic settings file creation.
    static let hooksDictionary: [String: Any] = [
        "SessionStart": [["hooks": [["type": "command", "command": "open -g \"singlepane://hook?tab=$SP_TAB_ID&event=hello\""]]]],
        "SessionEnd": [["hooks": [["type": "command", "command": "open -g \"singlepane://hook?tab=$SP_TAB_ID&event=end\""]]]],
        "UserPromptSubmit": [["hooks": [["type": "command", "command": bodyExtractCommand(field: "prompt", event: "prompt")]]]],
        "SubagentStart": [["hooks": [["type": "command", "command": "open -g \"singlepane://hook?tab=$SP_TAB_ID&event=agent\""]]]],
        "Stop": [["hooks": [["type": "command", "command": bodyExtractCommand(field: "last_assistant_message", event: "stop")]]]],
        "Notification": [["matcher": "permission_prompt", "hooks": [["type": "command", "command": "open -g \"singlepane://hook?tab=$SP_TAB_ID&event=notification\""]]]],
    ]

    // MARK: - Actions

    @objc private func speakerToggled(_ sender: NSButton) {
        let event = VoicePack.hookEvents[sender.tag]
        let isMuted = sender.state == .on
        AudioManager.shared.setGlobalHookMuted(isMuted, event: event)
        applySpeakerAppearance(sender, muted: isMuted, theme: ThemeManager.shared.activeTheme)
    }

    @objc private func closeClicked() {
        guard let sheetWindow = view.window,
              let parentWindow = sheetWindow.sheetParent else { return }
        parentWindow.endSheet(sheetWindow)
    }
}

// MARK: - Setup Instructions Sheet

/// Modal sheet with 3-step instructions for enabling Claude Code hooks:
///   1. Copy the hooks JSON
///   2. Open the settings file (clickable underlined link — creates if missing)
///   3. Add the JSON to the file and save
@MainActor
final class HookSetupInstructionsViewController: NSViewController {

    private let hooksJSON: String
    private let settingsPath: String
    private var copyButton: NSButton!
    private var addButton: NSButton!

    init(hooksJSON: String, settingsPath: String) {
        self.hooksJSON = hooksJSON
        self.settingsPath = settingsPath
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 0))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme
        let font = FontManager.shared.activeFont
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        // Title
        let titleLabel = NSTextField(labelWithString: "Enable Claude Code Sound Hooks")
        let boldFont = NSFontManager.shared.convert(font.withSize(14), toHaveTrait: .boldFontMask)
        titleLabel.font = boldFont
        titleLabel.textColor = theme.hookYellow
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Intro
        let introLabel = NSTextField(wrappingLabelWithString:
            "Add hooks to your Claude Code settings so the app plays sounds on lifecycle events."
        )
        introLabel.font = font.withSize(11)
        introLabel.textColor = theme.chromeTextSecondary
        introLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(introLabel)

        // Step 1: JSON code block with copy button
        let step1Label = makeStepLabel("1. Copy the hooks JSON", theme: theme, font: font)
        view.addSubview(step1Label)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = theme.chromeBorder.cgColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textColor = theme.foregroundColor
        textView.backgroundColor = theme.backgroundColor
        textView.string = hooksJSON
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        view.addSubview(scrollView)

        copyButton = NSButton(title: "Copy JSON", target: self, action: #selector(copyJSON))
        copyButton.bezelStyle = .rounded
        copyButton.font = font.withSize(11)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyButton)

        // Step 2: Clickable file path link
        let step2Label = makeStepLabel("2. Open the settings file", theme: theme, font: font)
        view.addSubview(step2Label)

        let fileLink = NSButton()
        fileLink.isBordered = false
        fileLink.attributedTitle = makeUnderlinedFileLink(settingsPath, theme: theme, font: font)
        fileLink.target = self
        fileLink.action = #selector(fileLinkClicked)
        fileLink.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fileLink)

        let fileLinkHint = NSTextField(labelWithString: "(creates the file if it doesn't exist)")
        fileLinkHint.font = font.withSize(9)
        fileLinkHint.textColor = theme.chromeTextSecondary
        fileLinkHint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fileLinkHint)

        // Step 3: Add to settings button
        let step3Label = makeStepLabel("3. Paste the JSON into the file and save", theme: theme, font: font)
        view.addSubview(step3Label)

        let step3Hint = NSTextField(wrappingLabelWithString:
            "Or click below to add the hooks automatically:"
        )
        step3Hint.font = font.withSize(10)
        step3Hint.textColor = theme.chromeTextSecondary
        step3Hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(step3Hint)

        addButton = NSButton(title: "Add to Settings & Save", target: self, action: #selector(addToSettings))
        addButton.bezelStyle = .rounded
        addButton.font = font.withSize(11)
        addButton.contentTintColor = theme.hookGreen
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)

        // Done button
        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.font = font.withSize(13)
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            introLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            introLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            introLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Step 1
            step1Label.topAnchor.constraint(equalTo: introLabel.bottomAnchor, constant: 16),
            step1Label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            scrollView.topAnchor.constraint(equalTo: step1Label.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(equalToConstant: 140),

            copyButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            // Step 2
            step2Label.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 14),
            step2Label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            fileLink.topAnchor.constraint(equalTo: step2Label.bottomAnchor, constant: 4),
            fileLink.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),

            fileLinkHint.leadingAnchor.constraint(equalTo: fileLink.trailingAnchor, constant: 6),
            fileLinkHint.centerYAnchor.constraint(equalTo: fileLink.centerYAnchor),

            // Step 3
            step3Label.topAnchor.constraint(equalTo: fileLink.bottomAnchor, constant: 14),
            step3Label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            step3Hint.topAnchor.constraint(equalTo: step3Label.bottomAnchor, constant: 4),
            step3Hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            step3Hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            addButton.topAnchor.constraint(equalTo: step3Hint.bottomAnchor, constant: 6),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),

            // Done
            doneButton.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Helpers

    /// Creates a bold step label (e.g., "1. Copy the hooks JSON").
    private func makeStepLabel(_ text: String, theme: Theme, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFontManager.shared.convert(font.withSize(12), toHaveTrait: .boldFontMask)
        label.textColor = theme.chromeText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Creates an underlined, yellow-tinted attributed string for the file path link.
    private func makeUnderlinedFileLink(_ path: String, theme: Theme, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: path, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: theme.hookYellow,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: theme.hookYellow.withAlphaComponent(0.5),
            .cursor: NSCursor.pointingHand,
        ])
    }

    // MARK: - Actions

    @objc private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hooksJSON, forType: .string)
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy JSON"
        }
    }

    /// Opens the settings file in the app's editor, creating it if it doesn't exist.
    @objc private func fileLinkClicked() {
        let path = settingsPath
        let fileManager = FileManager.default

        // Ensure ~/.claude directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Create settings.json with empty object if it doesn't exist
        if !fileManager.fileExists(atPath: path) {
            try? "{\n}\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        // Dismiss this sheet, then open the file in the app's editor
        guard let sheetWindow = view.window,
              let parentWindow = sheetWindow.sheetParent else { return }
        parentWindow.endSheet(sheetWindow)

        let url = URL(fileURLWithPath: path)
        if let workspace = findWorkspaceViewController(from: parentWindow) {
            workspace.openFileInEditor(url)
        }
    }

    /// Writes hooks into the settings file, creating it if needed.
    @objc private func addToSettings() {
        let path = settingsPath
        let fileManager = FileManager.default

        // Ensure ~/.claude directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Read existing settings or start with empty object
        var settingsDict: [String: Any]
        if let data = fileManager.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settingsDict = json
        } else {
            settingsDict = [:]
        }

        // Deep merge: append our hook entries per event, preserving existing hooks.
        // Skip an event if our exact command is already present to avoid duplicates.
        let ourHooks = HookMuteEditorViewController.hooksDictionary
        var existingHooks = settingsDict["hooks"] as? [String: Any] ?? [:]

        for (eventKey, ourEntries) in ourHooks {
            guard let ourArray = ourEntries as? [[String: Any]] else { continue }
            var eventArray = existingHooks[eventKey] as? [[String: Any]] ?? []

            for ourEntry in ourArray {
                // Check if this exact hook command already exists in the event array
                let ourCommand = Self.extractCommand(from: ourEntry)
                let alreadyExists = eventArray.contains { existing in
                    Self.extractCommand(from: existing) == ourCommand && ourCommand != nil
                }
                if !alreadyExists {
                    eventArray.append(ourEntry)
                }
            }

            existingHooks[eventKey] = eventArray
        }

        settingsDict["hooks"] = existingHooks

        guard let data = try? JSONSerialization.data(
            withJSONObject: settingsDict,
            options: [.prettyPrinted, .sortedKeys]
        ), let jsonString = String(data: data, encoding: .utf8) else {
            NSLog("Failed to serialize settings JSON")
            return
        }

        do {
            try jsonString.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Failed to write settings: \(error)")
            return
        }

        addButton.title = "Added!"
        addButton.contentTintColor = ThemeManager.shared.activeTheme.chromeText
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.addButton.title = "Add to Settings & Save"
            self?.addButton.contentTintColor = ThemeManager.shared.activeTheme.hookGreen
        }
    }

    /// Extracts the "command" string from a hook entry by drilling into
    /// `{"hooks": [{"command": "..."}]}`. Returns nil if the structure doesn't match.
    private static func extractCommand(from entry: [String: Any]) -> String? {
        guard let hooks = entry["hooks"] as? [[String: Any]],
              let first = hooks.first,
              let command = first["command"] as? String else {
            return nil
        }
        return command
    }

    @objc private func doneClicked() {
        guard let sheetWindow = view.window,
              let parentWindow = sheetWindow.sheetParent else { return }
        parentWindow.endSheet(sheetWindow)
    }

    // MARK: - Window Traversal

    /// Finds the WorkspaceViewController from the window's content view controller hierarchy.
    private func findWorkspaceViewController(from window: NSWindow) -> WorkspaceViewController? {
        var vc: NSViewController? = window.contentViewController
        while let viewController = vc {
            if let workspace = viewController as? WorkspaceViewController { return workspace }
            // Search children breadth-first
            for child in viewController.children {
                if let workspace = child as? WorkspaceViewController { return workspace }
            }
            vc = viewController.children.first
        }
        return nil
    }
}
