// LayoutBarView.swift
// Thin toolbar strip with a single active layout icon (+ ▾ chevron) that opens
// a rich Layout Manager popover. Also contains theme, font, voice, mute, and
// notification controls on the right side.

import AppKit

// MARK: - Delegate Protocol

/// Notifies the parent when the user interacts with layout presets or custom layouts.
@MainActor
protocol LayoutBarDelegate: AnyObject {
    func layoutBarDidSelectLayout(_ layout: SnapLayout)
    func layoutBarDidSelectCustomLayout(_ layout: CustomLayout)
    func layoutBarDidRequestSaveCustomLayout()
    func layoutBarDidRequestDeleteCustomLayout(at index: Int)
    /// Called when the user reorders columns via the Layout Manager popover.
    func layoutBarDidReorderColumns(_ newOrder: [PanelType])
}

// MARK: - LayoutBarView

@MainActor
final class LayoutBarView: NSView {

    // MARK: - Properties

    weak var delegate: LayoutBarDelegate?

    private let stackView = NSStackView()

    /// Single icon showing the active layout with a dropdown chevron.
    private let activeIcon = ActiveLayoutIconView()

    /// Active layout manager popover (nil when not showing).
    private var layoutPopover: NSPopover?

    private let feedbackButton = NSButton(frame: .zero)

    private let themeButton = NSButton(frame: .zero)
    private let themeMenu = NSMenu()
    private let fontButton = NSButton(frame: .zero)
    private let fontMenu = NSMenu()
    private let voiceButton = NSButton(frame: .zero)
    private let muteButton = NSButton(frame: .zero)
    private let notificationButton = NSButton(frame: .zero)

    /// The column order used to draw icon rectangles in the correct position.
    private(set) var columnOrder: [PanelType]

    /// Tracks the currently active layout for the trigger icon and popover highlight.
    private(set) var activeLayoutState: ActiveLayoutState = .preset(.allEqual)

    // MARK: - Constants

    static let barHeight: CGFloat = 36

    /// 1px bottom border to separate the bar from the panels below.
    private let bottomBorder = NSView()

    // MARK: - Init

    init(columnOrder: [PanelType]) {
        self.columnOrder = columnOrder
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true

        // Bottom border — 1px line separating the bar from the panels below
        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = ThemeManager.shared.activeTheme.chromeBorder.cgColor
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)

        // Configure stack view — left-aligned, horizontal
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        // Feedback button — rightmost, accent-colored pill
        feedbackButton.translatesAutoresizingMaskIntoConstraints = false
        feedbackButton.bezelStyle = .inline
        feedbackButton.isBordered = false
        feedbackButton.wantsLayer = true
        feedbackButton.layer?.cornerRadius = 6
        feedbackButton.font = FontManager.shared.activeFont.withSize(11)
        feedbackButton.controlSize = .small
        feedbackButton.title = "Feedback"
        feedbackButton.contentTintColor = .black
        feedbackButton.alignment = .center
        feedbackButton.target = self
        feedbackButton.action = #selector(feedbackButtonClicked(_:))
        applyFeedbackButtonTheme()
        addSubview(feedbackButton)

        // Theme picker — button that pops menu downward to show all themes
        themeButton.translatesAutoresizingMaskIntoConstraints = false
        themeButton.bezelStyle = .inline
        themeButton.font = FontManager.shared.activeFont.withSize(11)
        themeButton.controlSize = .small
        themeButton.alignment = .center
        themeButton.target = self
        themeButton.action = #selector(themeButtonClicked(_:))
        themeButton.title = ThemeManager.shared.activeTheme.name
        addSubview(themeButton)
        buildThemeMenu()

        // Font picker — button that pops menu downward to show all fonts
        fontButton.translatesAutoresizingMaskIntoConstraints = false
        fontButton.bezelStyle = .inline
        fontButton.font = FontManager.shared.activeFont.withSize(11)
        fontButton.controlSize = .small
        fontButton.alignment = .center
        fontButton.target = self
        fontButton.action = #selector(fontButtonClicked(_:))
        fontButton.title = FontManager.shared.activeFontName
        addSubview(fontButton)
        buildFontMenu()

        // Voice pack picker — next to font picker
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.bezelStyle = .inline
        voiceButton.font = FontManager.shared.activeFont.withSize(11)
        voiceButton.controlSize = .small
        voiceButton.alignment = .center
        voiceButton.target = self
        voiceButton.action = #selector(voiceButtonClicked(_:))
        updateVoiceButtonTitle()
        addSubview(voiceButton)

        // Mute toggle — next to voice picker
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.bezelStyle = .inline
        muteButton.isBordered = false
        muteButton.setButtonType(.toggle)
        muteButton.font = NSFont.systemFont(ofSize: 12)
        muteButton.target = self
        muteButton.action = #selector(muteButtonClicked(_:))
        muteButton.state = AudioManager.shared.isMuted ? .on : .off
        updateMuteButtonAppearance()
        addSubview(muteButton)

        // Notification toggle — next to mute button
        notificationButton.translatesAutoresizingMaskIntoConstraints = false
        notificationButton.bezelStyle = .inline
        notificationButton.isBordered = false
        notificationButton.setButtonType(.toggle)
        notificationButton.font = NSFont.systemFont(ofSize: 12)
        notificationButton.target = self
        notificationButton.action = #selector(notificationButtonClicked(_:))
        notificationButton.state = UserDefaults.standard.bool(forKey: AppDelegate.notificationsDisabledKey) ? .on : .off
        updateNotificationButtonAppearance()
        addSubview(notificationButton)

        NSLayoutConstraint.activate([
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            feedbackButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            feedbackButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            feedbackButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            feedbackButton.heightAnchor.constraint(equalToConstant: 22),

            themeButton.trailingAnchor.constraint(equalTo: feedbackButton.leadingAnchor, constant: -8),
            themeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            themeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            themeButton.heightAnchor.constraint(equalToConstant: 22),

            fontButton.trailingAnchor.constraint(equalTo: themeButton.leadingAnchor, constant: -8),
            fontButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fontButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            fontButton.heightAnchor.constraint(equalToConstant: 22),

            voiceButton.trailingAnchor.constraint(equalTo: fontButton.leadingAnchor, constant: -8),
            voiceButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            voiceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            voiceButton.heightAnchor.constraint(equalToConstant: 22),

            muteButton.trailingAnchor.constraint(equalTo: voiceButton.leadingAnchor, constant: -4),
            muteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 20),
            muteButton.heightAnchor.constraint(equalToConstant: 18),

            notificationButton.trailingAnchor.constraint(equalTo: muteButton.leadingAnchor, constant: -4),
            notificationButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            notificationButton.widthAnchor.constraint(equalToConstant: 20),
            notificationButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Active layout icon — single icon + ▾ chevron that opens the popover
        activeIcon.columnOrder = columnOrder
        activeIcon.onClick = { [weak self] in
            self?.showLayoutManagerPopover()
        }
        stackView.addArrangedSubview(activeIcon)
    }

    // MARK: - Feedback

    /// Opens a blank GitHub issue in the browser.
    @objc private func feedbackButtonClicked(_ sender: NSButton) {
        if let url = URL(string: "https://github.com/jasonwilmot/singlepane/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Layout Manager Popover

    /// Opens the Layout Manager popover anchored below the active layout icon.
    private func showLayoutManagerPopover() {
        // Close existing popover if already open
        layoutPopover?.close()

        let popover = NSPopover()
        let vc = LayoutManagerPopoverViewController(columnOrder: columnOrder)
        vc.activeLayoutState = activeLayoutState
        vc.popoverDelegate = self
        vc.owningPopover = popover
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.show(relativeTo: activeIcon.bounds, of: activeIcon, preferredEdge: .maxY)
        layoutPopover = popover
    }

    // MARK: - Selection

    /// Programmatically select a preset layout, update the trigger icon, and notify delegate.
    func selectLayout(_ layout: SnapLayout) {
        activeLayoutState = .preset(layout)
        activeIcon.layoutState = activeLayoutState
        activeIcon.columnOrder = columnOrder
        delegate?.layoutBarDidSelectLayout(layout)
    }

    /// Programmatically select a custom layout, update the trigger icon, and notify delegate.
    /// Also syncs column order to the custom layout's saved order (each custom layout
    /// can have a different panel arrangement).
    func selectCustomLayout(_ layout: CustomLayout) {
        activeLayoutState = .custom(layout)
        columnOrder = layout.columnOrder
        activeIcon.layoutState = activeLayoutState
        activeIcon.columnOrder = layout.columnOrder
        delegate?.layoutBarDidSelectCustomLayout(layout)
    }

    /// Called on manual divider drag — keeps the current icon but removes "active" styling.
    /// Note: We no longer clear selection since we always show an active layout.
    func clearSelection() {
        // No-op: the active layout icon always shows the last-selected layout.
    }

    /// Sets the initial active layout without triggering the delegate.
    func highlightLayout(_ layout: SnapLayout) {
        activeLayoutState = .preset(layout)
        activeIcon.layoutState = activeLayoutState
        activeIcon.columnOrder = columnOrder
    }

    /// Updates the column order displayed by the active icon.
    func updateColumnOrder(_ newOrder: [PanelType]) {
        columnOrder = newOrder
        activeIcon.columnOrder = newOrder
    }

    /// Called after custom layout save/delete (no-op now that the "+" button
    /// lives exclusively inside the popover).
    func reloadCustomLayouts() {
    }

    // MARK: - Theme Picker

    /// Builds the theme menu with color swatch previews for each theme.
    private func buildThemeMenu() {
        themeMenu.removeAllItems()
        themeMenu.minimumWidth = 220
        themeMenu.showsStateColumn = false

        let manager = ThemeManager.shared
        let menuFont = FontManager.shared.activeFont.withSize(11)
        let activeThemeName = manager.activeTheme.name
        for theme in manager.availableThemes {
            let item = NSMenuItem(title: theme.name, action: #selector(themeMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.view = ThemeSwatchMenuItemView(
                theme: theme,
                font: menuFont,
                isSelected: theme.name == activeThemeName
            )
            themeMenu.addItem(item)
        }
    }

    /// Shows the theme menu below the button so all items are visible without scrolling.
    @objc private func themeButtonClicked(_ sender: NSButton) {
        let origin = NSPoint(x: 0, y: sender.bounds.height + 2)
        themeMenu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func themeMenuItemSelected(_ sender: NSMenuItem) {
        ThemeManager.shared.selectTheme(named: sender.title)
        themeButton.title = sender.title
    }

    // MARK: - Font Picker

    /// Builds the font menu with each item showing its name and a sample string
    /// rendered in the font's own typeface so differences are visible.
    private func buildFontMenu() {
        fontMenu.removeAllItems()
        fontMenu.minimumWidth = 320
        fontMenu.showsStateColumn = false

        let manager = FontManager.shared
        let isActive = manager.activeFontName
        for preset in manager.availableFonts {
            let item = NSMenuItem(title: preset.displayName, action: #selector(fontMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.view = FontMenuItemView(
                preset: preset,
                isSelected: preset.displayName == isActive
            )
            fontMenu.addItem(item)
        }
    }

    /// Shows the font menu below the button so all items are visible without scrolling.
    @objc private func fontButtonClicked(_ sender: NSButton) {
        let origin = NSPoint(x: 0, y: sender.bounds.height + 2)
        fontMenu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func fontMenuItemSelected(_ sender: NSMenuItem) {
        FontManager.shared.selectFont(named: sender.title)
        fontButton.title = sender.title
    }

    // MARK: - Voice Pack Picker

    /// Updates the voice button title to reflect the active voice pack.
    /// Shows the short name (everything before the first "-"), trimmed.
    private func updateVoiceButtonTitle() {
        let manager = AudioManager.shared
        let activePack = manager.availableVoicePacks.first(
            where: { $0.directoryName == manager.selectedVoicePack }
        )
        let fullName = activePack?.displayName ?? "Voice"
        let shortName = fullName.split(separator: "-", maxSplits: 1).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? fullName
        voiceButton.title = shortName
    }

    /// Opens a voice picker menu with play-preview buttons next to each voice name.
    /// Sound packs appear at the top, separated from voice packs by a divider.
    /// Custom packs appear in a "My Packs" section with gear icons.
    /// A "Create My Own" item appears at the bottom.
    @objc private func voiceButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let manager = AudioManager.shared
        var didAddVoiceSeparator = false
        var didAddCustomSeparator = false

        for pack in manager.availableVoicePacks {
            // Insert a separator between sound packs and bundled voice packs
            if !pack.isSoundPack && !pack.isCustom && !didAddVoiceSeparator {
                menu.addItem(.separator())
                didAddVoiceSeparator = true
            }

            // Insert a separator + header before the first custom pack
            if pack.isCustom && !didAddCustomSeparator {
                menu.addItem(.separator())
                let header = NSMenuItem()
                header.view = VoiceMenuSectionHeaderView(title: "My Packs")
                menu.addItem(header)
                didAddCustomSeparator = true
            }

            let item = NSMenuItem()
            let view = VoiceMenuItemView(
                voicePack: pack,
                isSelected: pack.directoryName == manager.selectedVoicePack,
                onSelect: { [weak self] (dirName: String) in
                    AudioManager.shared.selectVoicePack(named: dirName)
                    self?.updateVoiceButtonTitle()
                    menu.cancelTracking()
                },
                onPreview: { (dirName: String) in
                    AudioManager.shared.previewVoice(directoryName: dirName)
                },
                onEdit: pack.isCustom ? { [weak self] (dirName: String) in
                    menu.cancelTracking()
                    self?.presentCustomPackEditor(packName: dirName)
                } : nil
            )
            item.view = view
            menu.addItem(item)
        }

        // "Create My Own", "Settings", and "How to Enable" items at the bottom
        menu.addItem(.separator())
        let createItem = NSMenuItem()
        createItem.view = VoiceMenuActionItemView(
            title: "Create My Own",
            symbolName: "plus.circle",
            action: { [weak self] in
                menu.cancelTracking()
                self?.presentCustomPackEditor(packName: nil)
            }
        )
        menu.addItem(createItem)

        let settingsItem = NSMenuItem()
        settingsItem.view = VoiceMenuActionItemView(
            title: "Settings",
            symbolName: "gearshape",
            action: { [weak self] in
                menu.cancelTracking()
                self?.presentHookMuteEditor()
            }
        )
        menu.addItem(settingsItem)

        // "How to Enable" — yellow, standalone item that opens the setup instructions modal
        let enableItem = NSMenuItem()
        enableItem.view = VoiceMenuActionItemView(
            title: "How to Enable",
            symbolName: "bolt.fill",
            tintColor: ThemeManager.shared.activeTheme.hookYellow,
            action: { [weak self] in
                menu.cancelTracking()
                self?.presentHookSetupInstructions()
            }
        )
        menu.addItem(enableItem)

        let point = NSPoint(x: 0, y: sender.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    // MARK: - Custom Pack Editor

    /// Presents the custom pack editor sheet.
    /// Pass nil for `packName` to create a new pack; pass an existing name to edit.
    private func presentCustomPackEditor(packName: String?) {
        guard let window = self.window else { return }
        let editor = CustomPackEditorViewController(editingPackName: packName)
        editor.onDismiss = { [weak self] in
            AudioManager.shared.refreshVoicePacks()
            self?.updateVoiceButtonTitle()
        }
        let sheetWindow = NSWindow(contentViewController: editor)
        sheetWindow.styleMask = [.titled, .closable, .resizable]
        sheetWindow.title = packName != nil ? "Edit Pack" : "Create Custom Pack"
        window.beginSheet(sheetWindow)
    }

    // MARK: - Hook Mute Editor

    /// Presents the global hook mute settings sheet.
    private func presentHookMuteEditor() {
        guard let window = self.window else { return }
        let editor = HookMuteEditorViewController()
        let sheetWindow = NSWindow(contentViewController: editor)
        sheetWindow.styleMask = [.titled, .closable]
        sheetWindow.title = "Sound Settings"
        window.beginSheet(sheetWindow)
    }

    // MARK: - How to Enable (Setup Instructions)

    /// Presents the hook setup instructions modal directly from the voice dropdown.
    private func presentHookSetupInstructions() {
        guard let window = self.window else { return }
        let setupVC = HookSetupInstructionsViewController(
            hooksJSON: HookMuteEditorViewController.hooksJSON,
            settingsPath: HookMuteEditorViewController.settingsPath
        )
        let sheetWindow = NSWindow(contentViewController: setupVC)
        sheetWindow.styleMask = [.titled, .closable]
        sheetWindow.title = "Enable Claude Code Hooks"
        window.beginSheet(sheetWindow)
    }

    // MARK: - Mute Toggle

    @objc private func muteButtonClicked(_ sender: NSButton) {
        AudioManager.shared.isMuted = (sender.state == .on)
        updateMuteButtonAppearance()
    }

    /// Updates the mute button icon and color based on current mute state.
    private func updateMuteButtonAppearance() {
        let isMuted = AudioManager.shared.isMuted
        let theme = ThemeManager.shared.activeTheme
        let symbolName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isMuted ? "Unmute" : "Mute")
        muteButton.contentTintColor = isMuted ? theme.hookRed : theme.hookGreen
        muteButton.toolTip = isMuted ? "Unmute audio" : "Mute audio"
    }

    // MARK: - Notification Toggle

    @objc private func notificationButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: AppDelegate.notificationsDisabledKey)
        updateNotificationButtonAppearance()
    }

    /// Updates the notification button icon based on current disabled state.
    private func updateNotificationButtonAppearance() {
        let isDisabled = UserDefaults.standard.bool(forKey: AppDelegate.notificationsDisabledKey)
        let symbolName = isDisabled ? "bell.slash.fill" : "bell.fill"
        notificationButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isDisabled ? "Enable notifications" : "Disable notifications")
        notificationButton.contentTintColor = isDisabled
            ? ThemeManager.shared.activeTheme.chromeTextSecondary
            : ThemeManager.shared.activeTheme.chromeText
        notificationButton.toolTip = isDisabled ? "Enable system notifications" : "Disable system notifications"
    }

    // MARK: - Theme Appearance

    /// Applies the active theme to the layout bar background and redraws icons.
    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme
        layer?.backgroundColor = theme.chromeBackground.cgColor
        activeIcon.needsDisplay = true
        bottomBorder.layer?.backgroundColor = theme.chromeBorder.cgColor
        themeButton.title = theme.name
        applyFeedbackButtonTheme()
        updateMuteButtonAppearance()
        updateNotificationButtonAppearance()
    }

    /// Styles the feedback pill with the current theme accent color.
    private func applyFeedbackButtonTheme() {
        feedbackButton.layer?.backgroundColor = ThemeManager.shared.activeTheme.chromeAccent.cgColor
    }

    /// Watches ThemeManager for changes and re-applies colors.
    func startObservingTheme() {
        withObservationTracking {
            _ = ThemeManager.shared.activeTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.startObservingTheme()
            }
        }
    }

    // MARK: - Font Appearance

    /// Applies the active font to the layout bar popups.
    func applyFont() {
        let font = FontManager.shared.activeFont
        themeButton.font = font.withSize(11)
        fontButton.font = font.withSize(11)
        fontButton.title = FontManager.shared.activeFontName
        voiceButton.font = font.withSize(11)
        feedbackButton.font = font.withSize(11)
        // Rebuild menus so labels use the new font
        buildThemeMenu()
        buildFontMenu()
    }

    /// Watches FontManager for changes and re-applies fonts.
    func startObservingFont() {
        withObservationTracking {
            _ = FontManager.shared.activeFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFont()
                self?.startObservingFont()
            }
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        super.resetCursorRects()
        let buttons: [NSView] = [
            feedbackButton, themeButton, fontButton, voiceButton,
            muteButton, notificationButton, activeIcon,
        ]
        for button in buttons where !button.isHidden {
            button.discardCursorRects()
            let rect = convert(button.bounds, from: button)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight)
    }
}

// MARK: - LayoutManagerPopoverDelegate

extension LayoutBarView: LayoutManagerPopoverDelegate {

    func layoutManagerDidSelectLayout(_ layout: SnapLayout) {
        selectLayout(layout)
    }

    func layoutManagerDidSelectCustomLayout(_ layout: CustomLayout) {
        selectCustomLayout(layout)
    }

    func layoutManagerDidReorderColumns(_ newOrder: [PanelType]) {
        updateColumnOrder(newOrder)
        delegate?.layoutBarDidReorderColumns(newOrder)
    }

    func layoutManagerDidRequestSaveCustomLayout() {
        delegate?.layoutBarDidRequestSaveCustomLayout()
        reloadCustomLayouts()
    }

    func layoutManagerDidRequestDeleteCustomLayout(at index: Int) {
        delegate?.layoutBarDidRequestDeleteCustomLayout(at: index)
        reloadCustomLayouts()
    }
}

// MARK: - Font Menu Item

/// Custom menu item view that shows the font name (in the font itself) and a
/// sample string so the user can see how each typeface actually looks.
/// Layout matches VoiceMenuItemView: icon column (8px leading, 18×18), 4px gap, label.
private final class FontMenuItemView: NSView {

    private let preset: FontPreset
    private let isSelected: Bool

    /// Sample characters that highlight differences between monospace fonts.
    private static let sample = "0O 1lI {}=>"
    private static let itemHeight: CGFloat = 28
    /// Leading edge inset — matches VoiceMenuItemView's playButton leading.
    private static let iconLeading: CGFloat = 8
    /// Icon column width — matches VoiceMenuItemView's 18×18 play button.
    private static let iconWidth: CGFloat = 18
    /// Gap between icon column and text — matches VoiceMenuItemView.
    private static let iconTextGap: CGFloat = 4
    /// Trailing padding for sample text.
    private static let trailingPad: CGFloat = 10

    /// X where the label text begins (icon leading + icon width + gap).
    private static let textLeading: CGFloat = iconLeading + iconWidth + iconTextGap

    init(preset: FontPreset, isSelected: Bool) {
        self.preset = preset
        self.isSelected = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: Self.itemHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: Self.itemHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted == true
        let theme = ThemeManager.shared.activeTheme

        // Selected row background (not highlighted) — subtle fill like VoiceMenuItemView
        if isSelected && !highlighted {
            theme.chromeText.withAlphaComponent(0.12).setFill()
            bounds.fill()
        }

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }

        let textColor: NSColor = highlighted ? .white : theme.chromeText
        let dimColor: NSColor = highlighted ? .white.withAlphaComponent(0.6) : theme.chromeTextSecondary

        // Checkmark icon for the selected font — same position as VoiceMenuItemView's play icon
        if isSelected {
            let checkConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let checkColor = NSImage.SymbolConfiguration(paletteColors: [highlighted ? .white : theme.chromeAccent])
            if let checkImage = NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: "Selected"
            )?.withSymbolConfiguration(checkConfig.applying(checkColor)) {
                let iconRect = NSRect(
                    x: Self.iconLeading + (Self.iconWidth - checkImage.size.width) / 2,
                    y: (bounds.height - checkImage.size.height) / 2,
                    width: checkImage.size.width,
                    height: checkImage.size.height
                )
                checkImage.draw(in: iconRect)
            }
        }

        // Resolve the font for this preset
        let font = NSFont(name: preset.fontFamily, size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Draw font name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let nameStr = preset.displayName as NSString
        let nameSize = nameStr.size(withAttributes: nameAttrs)
        let nameY = (bounds.height - nameSize.height) / 2
        nameStr.draw(at: NSPoint(x: Self.textLeading, y: nameY), withAttributes: nameAttrs)

        // Draw sample string right-aligned in a dimmer color
        let sampleAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dimColor,
        ]
        let sampleStr = Self.sample as NSString
        let sampleSize = sampleStr.size(withAttributes: sampleAttrs)
        let sampleX = bounds.width - Self.trailingPad - sampleSize.width
        let sampleY = (bounds.height - sampleSize.height) / 2
        sampleStr.draw(at: NSPoint(x: sampleX, y: sampleY), withAttributes: sampleAttrs)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let menuItem = enclosingMenuItem, let menu = menuItem.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: menuItem))
    }
}

// MARK: - Theme Swatch Menu Item

/// Custom menu item view showing a theme name alongside color swatch blocks.
/// Displays: bg, fg, red, green, yellow, blue, magenta, cyan from the theme palette.
/// Layout matches FontMenuItemView / VoiceMenuItemView: icon column + text + trailing content.
private final class ThemeSwatchMenuItemView: NSView {

    private let theme: Theme
    private let font: NSFont
    private let isSelected: Bool

    /// Swatch block size and spacing.
    private static let swatchSize: CGFloat = 10
    private static let swatchSpacing: CGFloat = 2
    private static let swatchCornerRadius: CGFloat = 2
    private static let itemHeight: CGFloat = 28
    /// Leading/trailing padding — matches voice/font menu icon column.
    private static let iconLeading: CGFloat = 8
    private static let iconWidth: CGFloat = 18
    private static let iconTextGap: CGFloat = 4
    private static let textLeading: CGFloat = iconLeading + iconWidth + iconTextGap
    private static let trailingPad: CGFloat = 10

    /// Palette indices for the swatch colors: red, green, yellow, blue, magenta, cyan.
    private static let paletteIndices = [1, 2, 3, 4, 5, 6]

    init(theme: Theme, font: NSFont, isSelected: Bool) {
        self.theme = theme
        self.font = font
        self.isSelected = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: Self.itemHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 280, height: Self.itemHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted == true
        let activeTheme = ThemeManager.shared.activeTheme

        // Selected row background — subtle fill matching font/voice menus
        if isSelected && !highlighted {
            activeTheme.chromeText.withAlphaComponent(0.12).setFill()
            bounds.fill()
        }

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }

        let textColor: NSColor = highlighted ? .white : activeTheme.chromeText
        let dimColor: NSColor = highlighted ? .white.withAlphaComponent(0.6) : activeTheme.chromeTextSecondary

        // Checkmark icon for the selected theme
        if isSelected {
            let checkConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let checkColor = NSImage.SymbolConfiguration(paletteColors: [highlighted ? .white : activeTheme.chromeAccent])
            if let checkImage = NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: "Selected"
            )?.withSymbolConfiguration(checkConfig.applying(checkColor)) {
                let iconRect = NSRect(
                    x: Self.iconLeading + (Self.iconWidth - checkImage.size.width) / 2,
                    y: (bounds.height - checkImage.size.height) / 2,
                    width: checkImage.size.width,
                    height: checkImage.size.height
                )
                checkImage.draw(in: iconRect)
            }
        }

        // Draw theme name
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let nameStr = theme.name as NSString
        let nameSize = nameStr.size(withAttributes: attrs)
        let textY = (bounds.height - nameSize.height) / 2
        nameStr.draw(at: NSPoint(x: Self.textLeading, y: textY), withAttributes: attrs)

        // Draw color swatches right-aligned
        let swatchColors = [theme.backgroundColor, theme.foregroundColor]
            + Self.paletteIndices.map { theme.paletteColor(at: $0) }
        let totalSwatchWidth = CGFloat(swatchColors.count) * Self.swatchSize
            + CGFloat(swatchColors.count - 1) * Self.swatchSpacing
        var x = bounds.width - Self.trailingPad - totalSwatchWidth
        let y = (bounds.height - Self.swatchSize) / 2

        for color in swatchColors {
            let rect = NSRect(x: x, y: y, width: Self.swatchSize, height: Self.swatchSize)
            let path = NSBezierPath(roundedRect: rect, xRadius: Self.swatchCornerRadius, yRadius: Self.swatchCornerRadius)
            color.setFill()
            path.fill()
            x += Self.swatchSize + Self.swatchSpacing
        }
    }

    // Redraw on highlight changes so selection background updates
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    // Forward mouse events so the menu item selection works
    override func mouseUp(with event: NSEvent) {
        guard let menuItem = enclosingMenuItem, let menu = menuItem.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: menuItem))
    }
}

// MARK: - Voice Menu Section Header

/// Non-interactive section header for the voice picker menu (e.g., "My Packs").
@MainActor
final class VoiceMenuSectionHeaderView: NSView {

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 20))
        let label = NSTextField(labelWithString: title)
        label.font = FontManager.shared.activeFont.withSize(9)
        label.textColor = ThemeManager.shared.activeTheme.chromeTextSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Voice Menu Action Item

/// Clickable action item for the voice picker menu (e.g., "Create My Own").
/// Displays an SF Symbol icon and label; invokes a closure on click.
@MainActor
final class VoiceMenuActionItemView: NSView {

    private let action: () -> Void

    init(title: String, symbolName: String, tintColor: NSColor? = nil, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        wantsLayer = true

        let theme = ThemeManager.shared.activeTheme
        let itemColor = tintColor ?? theme.chromeTextSecondary

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        icon.contentTintColor = itemColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let label = NSTextField(labelWithString: title)
        label.font = FontManager.shared.activeFont.withSize(11)
        label.textColor = tintColor ?? theme.chromeText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var isMouseInside = false

    override func draw(_ dirtyRect: NSRect) {
        if isMouseInside {
            ThemeManager.shared.activeTheme.chromeText.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        action()
    }
}
