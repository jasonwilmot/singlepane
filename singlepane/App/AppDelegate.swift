// AppDelegate.swift
// Manages app lifecycle, the single main window, and URL scheme handling.
// Handles singlepane:// URLs for hook-driven tab highlighting.
// Posts macOS system notifications on stop/notification hook events.

import AppKit
import CoreText
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var windowController: MainWindowController?
    private var workspaceVC: WorkspaceViewController?
    private var onboardingWindow: NSWindow?

    // MARK: - UserDefaults Keys

    /// Whether system notifications are disabled by the user.
    static let notificationsDisabledKey = "systemNotificationsDisabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the bundled Nerd Font symbols font so it's available
        // process-wide for font cascade fallback — must happen before any
        // views are created that use FontManager.
        registerBundledFonts()

        // Set notification delegate and register action categories early so
        // clicks on delivered notifications route correctly.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerNotificationCategories(center)

        // Register for GetURL Apple Events explicitly. The delegate method
        // application(_:open:) isn't reliably called when multiple builds
        // exist in DerivedData. This direct handler is more robust.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Build the menu bar programmatically
        NSApp.mainMenu = MainMenuBuilder.build()

        if OnboardingPermissionsViewController.hasCompleted {
            // Onboarding already done — create workspace and show immediately.
            createAndShowMainWindow()
        } else {
            // First launch — show the permissions onboarding screen.
            // The workspace is created AFTER onboarding to avoid triggering
            // TCC file access prompts before the user is ready.
            showOnboarding()
        }

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Single-window app — quit when the window closes.
        // Don't quit while the onboarding window is still open.
        onboardingWindow == nil
    }

    // MARK: - Onboarding

    /// Creates the workspace and main window, then shows it.
    /// Restores the user's saved column order if available.
    private func createAndShowMainWindow() {
        var config = LayoutConfiguration.default
        config.columnOrder = LayoutConfiguration.loadColumnOrder()
        config.terminalTabOrientation = LayoutConfiguration.loadTerminalTabOrientation()
        let workspace = WorkspaceViewController(configuration: config)
        self.workspaceVC = workspace
        windowController = MainWindowController(contentViewController: workspace)
        windowController?.showWindow(nil)
    }

    /// Presents the onboarding flow as a standalone window.
    /// Step 1: Welcome video → Step 2: Permissions → Main app.
    /// The workspace is created AFTER onboarding to avoid triggering
    /// TCC file access prompts before the user is ready.
    private func showOnboarding() {
        let welcomeVC = OnboardingWelcomeViewController()
        welcomeVC.onContinue = { [weak self] in
            self?.showPermissionsStep()
        }

        let window = makeOnboardingWindow(contentVC: welcomeVC)
        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Transitions the onboarding window to the permissions step.
    private func showPermissionsStep() {
        let permissionsVC = OnboardingPermissionsViewController()
        permissionsVC.onCompleted = { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.createAndShowMainWindow()
        }

        onboardingWindow?.contentViewController = permissionsVC
    }

    /// Creates the styled onboarding window shell.
    private func makeOnboardingWindow(contentVC: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: contentVC)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Velocity"
        window.isMovableByWindowBackground = true
        window.center()

        let theme = ThemeManager.shared.activeTheme
        window.backgroundColor = theme.chromeBackground

        return window
    }

    // MARK: - Debug Actions

    #if DEBUG
    /// Shows the onboarding screen on demand (Debug menu).
    @objc func debugShowOnboarding() {
        // Close existing onboarding window if open
        onboardingWindow?.close()
        onboardingWindow = nil
        showOnboarding()
    }

    /// Resets the onboarding completed flag so it shows again on next launch (Debug menu).
    @objc func debugResetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "onboardingVersion")
    }
    #endif

    // MARK: - Font Registration

    /// Registers bundled font files so they're available process-wide.
    /// Called once at launch before any views use FontManager.
    private func registerBundledFonts() {
        let fonts: [(name: String, ext: String)] = [
            ("SymbolsNerdFontMono-Regular", "ttf"),
            ("JetBrainsMono-Regular", "ttf"),
            ("FiraCode-Regular", "ttf"),
            ("CascadiaCode-Regular", "ttf"),
            ("Hack-Regular", "ttf"),
            ("GeistMono-Regular", "ttf"),
            ("VictorMono-Regular", "ttf"),
            ("Inconsolata-Regular", "ttf"),
            ("MapleMono-Regular", "ttf"),
            ("DepartureMono-Regular", "otf"),
            ("Iosevka-Regular", "ttf"),
        ]
        for font in fonts {
            guard let url = Bundle.main.url(forResource: font.name, withExtension: font.ext) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Notification Categories

    /// Notification category identifier for hook events.
    static let hookCategoryID = "hookEvent"

    /// Registers actionable notification categories so stop/notification banners
    /// show "Open Terminal" and "Dismiss" buttons.
    private func registerNotificationCategories(_ center: UNUserNotificationCenter) {
        let openAction = UNNotificationAction(
            identifier: "openTerminal",
            title: "Open Terminal",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "dismiss",
            title: "Dismiss",
            options: [.destructive]
        )
        let hookCategory = UNNotificationCategory(
            identifier: Self.hookCategoryID,
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([hookCategory])
    }

    // MARK: - URL Scheme Handling

    /// Handles singlepane:// URLs from Claude Code hooks.
    /// Format: singlepane://hook?tab=<UUID>&color=<hex>
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleHookURL(url)
        }
    }

    /// Apple Event handler for kAEGetURL — explicit URL routing.
    /// More reliable than the delegate method when multiple builds of the
    /// same bundle ID exist in DerivedData.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        handleHookURL(url)
    }

    private func handleHookURL(_ url: URL) {
        guard url.scheme == "singlepane", url.host == "hook" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        // Parse query parameters
        let tabID = queryItems.first(where: { $0.name == "tab" })?.value
        let colorHex = queryItems.first(where: { $0.name == "color" })?.value
        let event = queryItems.first(where: { $0.name == "event" })?.value
        let body = queryItems.first(where: { $0.name == "body" })?.value

        guard let tabID, let sessionID = UUID(uuidString: tabID) else {
            // No valid tab ID — still play audio if we have an event
            if let event { AudioManager.shared.playSound(event: event) }
            return
        }

        // Map event types to theme-adaptive colors if no explicit color provided.
        // Falls back to the active theme's ANSI palette colors.
        let theme = ThemeManager.shared.activeTheme
        let color: NSColor? = if let colorHex {
            NSColor.fromHex(colorHex)
        } else {
            switch event {
            case "prompt":       theme.hookYellow
            case "stop":         theme.hookGreen
            case "notification": theme.hookRed
            case "agent":        theme.hookPurple
            default:             nil
            }
        }

        // Determine spinner state from event type:
        // - "prompt" starts the spinner (user submitted a prompt, agent is thinking)
        // - "stop" / "notification" stop the spinner (agent finished or needs attention)
        // - "hello" / "end" / "agent" have no spinner effect
        let spinning: Bool? = switch event {
        case "prompt":       true
        case "stop":         false
        case "notification": false
        default:             nil
        }

        workspaceVC?.handleHookEvent(sessionID: sessionID, color: color, spinning: spinning)

        // Play audio after tab updates so it never blocks the visual feedback
        if let event { AudioManager.shared.playSound(event: event) }

        // Fire a system notification for stop/notification events so the user
        // knows a task finished or needs attention.
        if let event, event == "stop" || event == "notification" {
            let tabTitle = workspaceVC?.tabTitle(forSessionID: sessionID) ?? "Terminal"
            postSystemNotification(
                event: event,
                sessionID: sessionID,
                tabTitle: tabTitle,
                body: body
            )
        }
    }

    // MARK: - System Notifications

    /// Posts a macOS system notification for a hook event.
    /// Shows the prompt/response body text if available, with "Open Terminal" / "Dismiss" actions.
    private func postSystemNotification(event: String, sessionID: UUID, tabTitle: String, body: String?) {
        guard !UserDefaults.standard.bool(forKey: Self.notificationsDisabledKey) else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = event == "stop" ? "Task Complete" : "Attention Needed"
            content.subtitle = tabTitle
            content.sound = .default
            content.categoryIdentifier = Self.hookCategoryID
            content.userInfo = ["sessionID": sessionID.uuidString]

            // Show prompt/response text in the body if available
            if let body, !body.isEmpty {
                content.body = body
            }

            // Unique identifier per notification to prevent deduplication/replacement.
            // Small trigger delay improves macOS banner display reliability.
            let identifier = "hook-\(sessionID.uuidString)-\(event)-\(Date().timeIntervalSince1970)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification arrives while the app is in the foreground.
    /// Without this, the system silently swallows foreground notifications.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Called when the user clicks a notification or taps an action button.
    /// "Open Terminal" brings the app to front and switches to the session tab.
    /// "Dismiss" and default click also activate the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let uuidString = userInfo["sessionID"] as? String,
              let sessionID = UUID(uuidString: uuidString) else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case "dismiss", UNNotificationDismissActionIdentifier:
            // User dismissed — nothing to do
            break
        default:
            // "openTerminal" action or default click — activate and switch tab
            Task { @MainActor [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.workspaceVC?.selectTerminalTab(sessionID: sessionID)
            }
        }

        completionHandler()
    }
}
