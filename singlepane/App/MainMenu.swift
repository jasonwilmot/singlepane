// MainMenu.swift
// Builds the application menu bar programmatically. No XIB/Storyboard.
// Intentionally omits "New Window" — this is a single-window app.

import AppKit

@MainActor
enum MainMenuBuilder {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu())
        mainMenu.addItem(fileMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(viewMenu())
        mainMenu.addItem(windowMenu())
        #if DEBUG
        mainMenu.addItem(debugMenu())
        #endif
        return mainMenu
    }

    // MARK: - App Menu

    private static func appMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "About SinglePane",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide SinglePane",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                       action: #selector(NSApplication.hideOtherApplications(_:)),
                                       keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SinglePane",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - File Menu

    private static func fileMenu() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Edit Menu

    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Cut",
                     action: #selector(NSText.cut(_:)),
                     keyEquivalent: "x")
        menu.addItem(withTitle: "Copy",
                     action: #selector(NSText.copy(_:)),
                     keyEquivalent: "c")
        menu.addItem(withTitle: "Paste",
                     action: #selector(NSText.paste(_:)),
                     keyEquivalent: "v")
        menu.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)),
                     keyEquivalent: "a")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - View Menu

    private static func viewMenu() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Debug Menu

    #if DEBUG
    private static func debugMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Debug")
        menu.addItem(withTitle: "Show Onboarding",
                     action: #selector(AppDelegate.debugShowOnboarding),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Reset Onboarding",
                     action: #selector(AppDelegate.debugResetOnboarding),
                     keyEquivalent: "")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
    #endif

    // MARK: - Window Menu

    private static func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)),
                     keyEquivalent: "")

        let item = NSMenuItem()
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}
