// OnboardingPermissionsViewController.swift
// First-launch permissions screen inspired by Raycast's onboarding.
// Presents a two-column layout:
//   Left:  "Permissions" badge, headline, subtitle
//   Right: Permission rows with status buttons (Grant Access / Access Granted)
//
// Permissions requested:
//   1. Files and Folders — triggers macOS system prompt for Desktop/Documents/Downloads
//   2. Notifications — for hook event alerts when app is in background
//
// Files and Folders access is triggered by attempting to read a protected directory,
// which causes macOS to present its native permission dialog. Notifications use the
// standard UNUserNotificationCenter.requestAuthorization() API.

import AppKit
import UserNotifications

@MainActor
final class OnboardingPermissionsViewController: NSViewController {

    // MARK: - Properties

    /// Called when the user clicks Continue to dismiss the onboarding screen.
    var onCompleted: (() -> Void)?

    /// References to permission row pills for status updates.
    private var filesPill: PermissionPillButton!
    private var notifPill: PermissionPillButton!
    private var continueButton: NSButton!

    /// Tracks granted state for styling the Continue button.
    private var filesGranted = false { didSet { updateContinueButton() } }
    private var notifGranted = false { didSet { updateContinueButton() } }

    /// Timers that poll permission status after opening System Settings.
    private var filesPollingTimer: Timer?
    private var notifPollingTimer: Timer?

    private static let onboardingVersionKey = "onboardingVersion"
    private static let currentVersion = 1

    // MARK: - Onboarding Gate

    /// Returns true if the permissions onboarding has already been completed.
    static var hasCompleted: Bool {
        UserDefaults.standard.integer(forKey: onboardingVersionKey) >= currentVersion
    }

    /// Marks the permissions onboarding as completed.
    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: onboardingVersionKey)
    }

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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 860, height: 420)
        setupUI()
        refreshPermissionStates()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        filesPollingTimer?.invalidate()
        filesPollingTimer = nil
        notifPollingTimer?.invalidate()
        notifPollingTimer = nil
    }

    // MARK: - UI Setup

    private func setupUI() {
        let theme = ThemeManager.shared.activeTheme
        let font = FontManager.shared.activeFont

        view.wantsLayer = true
        view.layer?.backgroundColor = theme.chromeBackground.cgColor

        // Lock width to match the Step 1 welcome screen
        view.widthAnchor.constraint(equalToConstant: 860).isActive = true

        // --- Left Column ---
        let leftColumn = NSView()
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftColumn)

        // "Permissions" badge
        let badge = makeBadge("Step 2", theme: theme, font: font)
        leftColumn.addSubview(badge)

        // Headline
        let headline = NSTextField(labelWithString: "Let's get\nstarted")
        headline.maximumNumberOfLines = 2
        headline.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        headline.textColor = theme.chromeText
        headline.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addSubview(headline)

        // Subtitle
        let subtitle = NSTextField(wrappingLabelWithString:
            "We need to get a few things setup before we start vibing."
        )
        subtitle.font = font.withSize(12)
        subtitle.textColor = theme.chromeTextSecondary
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addSubview(subtitle)

        NSLayoutConstraint.activate([
            leftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            leftColumn.topAnchor.constraint(equalTo: view.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftColumn.widthAnchor.constraint(equalToConstant: 240),

            badge.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            badge.topAnchor.constraint(equalTo: leftColumn.topAnchor, constant: 60),

            headline.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            headline.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            headline.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 16),

            subtitle.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 12),
        ])

        // --- Right Column (Permission Rows) ---
        let rightColumn = NSView()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightColumn)

        // Vertical separator
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = theme.chromeBorder.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        // Permission rows
        let filesRow = makePermissionRow(
            icon: "folder.fill",
            title: "Files and Folders",
            description: "Allow reading and editing all your markdown files.",
            theme: theme,
            font: font,
            pillRef: &filesPill,
            onClick: { [weak self] in self?.grantFilesAccess() }
        )

        let notifRow = makePermissionRow(
            icon: "bell.badge.fill",
            title: "Notifications",
            description: "Alerts you when Claude is done or needs your attention.",
            theme: theme,
            font: font,
            pillRef: &notifPill,
            onClick: { [weak self] in self?.grantNotifications() }
        )

        // Row separator
        let rowSep = NSView()
        rowSep.wantsLayer = true
        rowSep.layer?.backgroundColor = theme.chromeBorder.cgColor
        rowSep.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView(views: [filesRow, rowSep, notifRow])
        rowStack.orientation = .vertical
        rowStack.spacing = 0
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addSubview(rowStack)

        // Continue button — larger with right arrow icon
        continueButton = NSButton(title: "", target: self, action: #selector(continueClicked))
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.keyEquivalent = "\r"
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        // Build attributed title: "Continue  →" with the arrow on the right
        let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Continue")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let attachment = NSTextAttachment()
        attachment.image = arrow
        let attrTitle = NSMutableAttributedString(
            string: "Continue  ",
            attributes: [
                .font: font.withSize(14),
                .foregroundColor: NSColor.white,
            ]
        )
        attrTitle.append(NSAttributedString(attachment: attachment))
        continueButton.attributedTitle = attrTitle

        rightColumn.addSubview(continueButton)

        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),
            separator.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 24),

            rightColumn.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 24),
            rightColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            rightColumn.topAnchor.constraint(equalTo: view.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rowStack.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            rowStack.centerYAnchor.constraint(equalTo: rightColumn.centerYAnchor, constant: -20),

            rowSep.heightAnchor.constraint(equalToConstant: 1),
            rowSep.leadingAnchor.constraint(equalTo: rowStack.leadingAnchor),
            rowSep.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor),

            filesRow.leadingAnchor.constraint(equalTo: rowStack.leadingAnchor),
            filesRow.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor),
            notifRow.leadingAnchor.constraint(equalTo: rowStack.leadingAnchor),
            notifRow.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor),

            continueButton.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            continueButton.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Permission Row Factory

    /// Creates a row with SF Symbol icon, title, description, and action button.
    private func makePermissionRow(
        icon: String,
        title: String,
        description: String,
        theme: Theme,
        font: NSFont,
        pillRef: inout PermissionPillButton!,
        onClick: @escaping () -> Void
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let rowIcon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        rowIcon.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        rowIcon.contentTintColor = theme.chromeTextSecondary
        rowIcon.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowIcon)

        // Title
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFontManager.shared.convert(font.withSize(13), toHaveTrait: .boldFontMask)
        titleLabel.textColor = theme.chromeText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        // Description
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = font.withSize(11)
        descLabel.textColor = theme.chromeTextSecondary
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(descLabel)

        // Pill button
        let pill = PermissionPillButton(font: font.withSize(12), onClick: onClick)
        pill.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(pill)
        pillRef = pill

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 72),

            rowIcon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            rowIcon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rowIcon.widthAnchor.constraint(equalToConstant: 32),
            rowIcon.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: rowIcon.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 16),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -12),

            pill.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            pill.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    // MARK: - Badge

    /// Creates a small colored pill label (e.g., "Permissions").
    private func makeBadge(_ text: String, theme: Theme, font: NSFont) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = theme.hookGreen.withAlphaComponent(0.2).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = NSFontManager.shared.convert(font.withSize(10), toHaveTrait: .boldFontMask)
        label.textColor = theme.hookGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
        ])

        return container
    }

    // MARK: - Permission Checks

    /// Checks current permission states and updates button appearance.
    /// Only checks notifications (safe to query without triggering a prompt).
    /// Files and Folders is NOT probed here — reading ~/Documents triggers the
    /// system dialog, which we only want when the user clicks "Grant Access".
    private func refreshPermissionStates() {
        // Files: default to not-granted — will update after user clicks Grant Access
        filesPill.applyState(granted: false)

        // Notifications: safe to check without triggering a prompt
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isAuthorized = settings.authorizationStatus == .authorized
            Task { @MainActor in
                guard let self else { return }
                self.notifGranted = isAuthorized
                self.notifPill.applyState(granted: isAuthorized)
            }
        }
    }

    /// TCC-protected directories we request access to.
    /// Each triggers its own macOS permission dialog on first access.
    private static let protectedDirectories = ["Documents", "Desktop", "Downloads"]

    /// Checks Files and Folders access by probing TCC-protected user directories.
    /// Returns true if the app can list at least one protected folder.
    static func hasFilesAndFoldersAccess() -> Bool {
        let home = NSHomeDirectory()
        return protectedDirectories.contains { folder in
            let path = home + "/" + folder
            return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
        }
    }

    // MARK: - Button State

    /// Styles the Continue button green when all permissions are granted.
    private func updateContinueButton() {
        let theme = ThemeManager.shared.activeTheme
        if filesGranted && notifGranted {
            continueButton.contentTintColor = theme.hookGreen
        } else {
            continueButton.contentTintColor = theme.chromeText
        }
    }

    // MARK: - Actions

    /// Triggers macOS Files and Folders permission prompts by attempting to
    /// access Documents, Desktop, and Downloads. Each triggers its own TCC
    /// dialog. Then polls until at least one is granted.
    private func grantFilesAccess() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Touch each protected directory — macOS queues one dialog per folder.
        for folder in Self.protectedDirectories {
            let url = home.appendingPathComponent(folder)
            _ = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
        }

        // Check immediately in case access was already granted
        if Self.hasFilesAndFoldersAccess() {
            filesGranted = true
            filesPill.applyState(granted: true)
            return
        }

        // Poll to detect when the user responds to the system dialog(s)
        filesPollingTimer?.invalidate()
        filesPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Self.hasFilesAndFoldersAccess() {
                    self.filesGranted = true
                    self.filesPill.applyState(granted: true)
                    self.filesPollingTimer?.invalidate()
                    self.filesPollingTimer = nil
                }
            }
        }
    }

    /// Requests notification permission. If the user has already responded to the
    /// system dialog (allowed or denied), `requestAuthorization` won't re-prompt —
    /// so we check the current status first and open System Settings if needed.
    private func grantNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .notDetermined:
                    // First time — show the system dialog
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                        Task { @MainActor in
                            guard let self else { return }
                            self.notifGranted = granted
                            self.notifPill.applyState(granted: granted)
                        }
                    }
                case .denied:
                    // Already denied — system won't re-prompt, must go to Settings
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                    NSWorkspace.shared.open(url)
                    self.startNotifPolling()
                case .authorized, .provisional, .ephemeral:
                    // Already granted
                    self.notifGranted = true
                    self.notifPill.applyState(granted: true)
                @unknown default:
                    break
                }
            }
        }
    }

    /// Polls notification settings until the user grants permission in System Settings.
    private func startNotifPolling() {
        notifPollingTimer?.invalidate()
        notifPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                let isAuthorized = settings.authorizationStatus == .authorized
                Task { @MainActor in
                    guard let self, isAuthorized else { return }
                    self.notifGranted = true
                    self.notifPill.applyState(granted: true)
                    self.notifPollingTimer?.invalidate()
                    self.notifPollingTimer = nil
                }
            }
        }
    }

    /// Marks onboarding complete and dismisses.
    @objc private func continueClicked() {
        filesPollingTimer?.invalidate()
        filesPollingTimer = nil
        notifPollingTimer?.invalidate()
        notifPollingTimer = nil
        Self.markCompleted()
        onCompleted?()
    }
}

// MARK: - Permission Pill Button

/// Custom pill-shaped clickable view that renders identically in both states.
/// Same shape, same padding, same corner radius — only the color changes.
///   • Not granted: filled dark background, white text, lock icon
///   • Granted: thin border, green text, green checkmark
/// Uses a closure for click handling — no NSButton/target-action issues.
@MainActor
final class PermissionPillButton: NSView {

    private static let green = NSColor(red: 0.13, green: 0.85, blue: 0.38, alpha: 1.0)
    private static let padding: CGFloat = 14
    private static let pillHeight: CGFloat = 34
    private static let cornerRadius: CGFloat = 8

    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let onClick: () -> Void
    private var isEnabled = true

    init(font: NSFont, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Label
        label.font = font
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.pillHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
        ])

        applyState(granted: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyState(granted: Bool) {
        let theme = ThemeManager.shared.activeTheme

        if granted {
            let color = Self.green
            label.stringValue = "Access Granted"
            label.textColor = color
            let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Granted")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
            img?.isTemplate = true
            iconView.image = img
            iconView.contentTintColor = color
            layer?.borderWidth = 1
            layer?.borderColor = color.cgColor
            layer?.backgroundColor = nil
            isEnabled = false
        } else {
            label.stringValue = "Grant Access"
            label.textColor = theme.chromeText
            let img = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Grant")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            img?.isTemplate = true
            iconView.image = img
            iconView.contentTintColor = theme.chromeText
            layer?.borderWidth = 0
            layer?.borderColor = nil
            layer?.backgroundColor = theme.chromeTextSecondary.withAlphaComponent(0.2).cgColor
            isEnabled = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onClick()
    }
}
