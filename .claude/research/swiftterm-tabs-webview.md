# SwiftTerm, Tab Bars, and Embedded Browsers for macOS AppKit

Research compiled: 2026-03-06

---

## 1. SwiftTerm -- Embedding a Terminal in an AppKit macOS App

### Package Information

| Field | Value |
|-------|-------|
| SPM URL | `https://github.com/migueldeicaza/SwiftTerm` |
| Latest version | **v1.11.2** (released February 20, 2025) |
| Swift tools version | 5.9 |
| macOS minimum | macOS 13+ |
| iOS minimum | iOS 14+ |
| Also supports | tvOS 13+, visionOS 1+ |
| License | MIT |
| GitHub stars | ~900 |
| Total releases | 19+ |
| Language | Swift |

**SPM dependency declaration:**
```swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.11.2")
]
```

**Recent release history:**
- v1.11.2 -- Feb 20, 2025
- v1.11.1 -- Feb 20, 2025
- v1.11.0 -- Feb 18, 2025
- v1.10.1 -- Feb 3, 2025
- v1.10.0 -- Feb 2, 2025
- v1.9.0 -- Jan 13, 2025
- v1.8.0 -- Jan 10, 2025
- v1.6.0 -- Dec 12, 2024

### Architecture Overview

SwiftTerm has a layered architecture:

1. **`Terminal`** -- The core engine. UI-agnostic VT100/Xterm terminal emulator. Handles escape sequence parsing, buffer management, scrollback, etc.
2. **`TerminalView`** (macOS) -- An `NSView` subclass that renders the terminal to screen. Located in `Sources/SwiftTerm/Mac/MacTerminalView.swift`. This is the visual component.
3. **`LocalProcess`** -- Manages a child process connected via a PTY (pseudo-terminal). Located in `Sources/SwiftTerm/LocalProcess.swift`.
4. **`LocalProcessTerminalView`** -- Convenience class that wires a `TerminalView` to a `LocalProcess`, giving you a self-contained terminal NSView. This is what you typically use.

### Key API: LocalProcess

```swift
public protocol LocalProcessDelegate: AnyObject {
    func processTerminated(_ source: LocalProcess, exitCode: Int32?)
    func dataReceived(slice: ArraySlice<UInt8>)
    func getWindowSize() -> winsize
}

public class LocalProcess {
    public private(set) var childfd: Int32
    public private(set) var shellPid: pid_t
    public private(set) var running: Bool

    public init(delegate: LocalProcessDelegate, dispatchQueue: DispatchQueue? = nil)

    public func startProcess(
        executable: String = "/bin/bash",
        args: [String] = [],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil
    )

    public func send(data: ArraySlice<UInt8>)
    public func terminate()
    public func setHostLogging(directory: String?)
}
```

### Key API: TerminalView (macOS NSView)

**Initialization:**
```swift
public init(frame: CGRect, font: NSFont?)
```

**Important Properties:**
```swift
public weak var terminalDelegate: TerminalViewDelegate?
public var font: NSFont { get set }
public var nativeForegroundColor: NSColor { get set }
public var nativeBackgroundColor: NSColor { get set }
public var caretColor: NSColor { get set }
public var caretTextColor: NSColor? { get set }
public var selectedTextBackgroundColor: NSColor { get set }
public var optionAsMetaKey: Bool                   // Treat Option as Meta key
public var backspaceSendsControlH: Bool
public var allowMouseReporting: Bool
public var useBrightColors: Bool
public var customBlockGlyphs: Bool { get set }
public var caretViewTracksFocus: Bool { get set }
public var notifyUpdateChanges: Bool
public var disableFullRedrawOnAnyChanges: Bool
```

**Important Methods:**
```swift
public func getTerminal() -> Terminal              // Access underlying Terminal engine
public func configureNativeColors()                // Apply system color scheme
public func getOptimalFrameSize() -> NSRect        // Calculate ideal frame for current cols/rows
public func resize(cols: Int, rows: Int)           // Programmatic resize
public func resetFontSize()

// Scrolling
public func pageUp()
public func pageDown()
public func scrollUp(lines: Int)
public func scrollDown(lines: Int)
public func scroll(toPosition: Double)
public var scrollThumbsize: CGFloat
public var scrollPosition: Double
public var canScroll: Bool

// Data I/O
public func feed(byteArray: ArraySlice<UInt8>)     // Feed raw bytes to terminal
public func feed(text: String)                      // Feed text string to terminal
public func send(data: ArraySlice<UInt8>)           // Send data (as if user typed)
public func send(txt: String)
public func send(_ bytes: [UInt8])

// Color management
public func installColors(_ colors: [Color])
public func setBackgroundColor(source: Terminal, color: Color)
public func setForegroundColor(source: Terminal, color: Color)

// Selection
public var selectionActive: Bool
public func getSelection() -> String?
public func selectAll()
public func selectNone()

// Scrollback
public func changeScrollback(_ newScrollback: Int?)

// Clipboard
@objc open func paste(_ sender: Any)
@objc open func copy(_ sender: Any)
```

### How to Create a LocalProcessTerminalView (Practical Usage)

The `LocalProcessTerminalView` is the simplest way to embed a working terminal. It is an `NSView` that internally creates a `LocalProcess` and wires it to a `TerminalView`.

**Basic embedding in an NSViewController:**
```swift
import SwiftTerm

class TerminalViewController: NSViewController, LocalProcessTerminalViewDelegate {
    var terminalView: LocalProcessTerminalView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Create the terminal view
        terminalView = LocalProcessTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.processDelegate = self

        // 2. Configure appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeForegroundColor = .textColor
        terminalView.nativeBackgroundColor = .textBackgroundColor
        terminalView.configureNativeColors()
        terminalView.optionAsMetaKey = true

        // 3. Add to view hierarchy
        view.addSubview(terminalView)

        // 4. Start the shell process
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: [],
            environment: nil,
            execName: nil,
            currentDirectory: NSHomeDirectory()
        )
    }

    // Delegate: called when shell process exits
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Handle shell exit (e.g., close tab, restart shell)
        print("Process terminated with exit code: \(exitCode ?? -1)")
    }

    // Delegate: terminal title changed (e.g., via escape sequences)
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Update tab title, window title, etc.
        view.window?.title = title
    }

    // Delegate: current directory changed
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Sync file browser to terminal CWD
    }

    // Delegate: terminal size changed
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // React to terminal resize
    }
}
```

### Managing Multiple Terminal Sessions (One Per Tab)

SwiftTerm does NOT provide tab management. Each `LocalProcessTerminalView` is an independent terminal session. You manage tabs yourself. The pattern is:

```swift
class TerminalSession {
    let id: UUID = UUID()
    let terminalView: LocalProcessTerminalView
    var title: String = "Terminal"
    var currentDirectory: String = NSHomeDirectory()
    var isRunning: Bool { terminalView.getTerminal().running }

    init(frame: NSRect) {
        terminalView = LocalProcessTerminalView(frame: frame)
        terminalView.autoresizingMask = [.width, .height]
    }

    func start(shell: String = "/bin/zsh", directory: String? = nil) {
        terminalView.startProcess(
            executable: shell,
            currentDirectory: directory ?? currentDirectory
        )
    }
}

class TerminalTabManager {
    var sessions: [TerminalSession] = []
    var activeSessionIndex: Int = 0
    var containerView: NSView

    var activeSession: TerminalSession? {
        guard sessions.indices.contains(activeSessionIndex) else { return nil }
        return sessions[activeSessionIndex]
    }

    func createNewTab(directory: String? = nil) -> TerminalSession {
        let session = TerminalSession(frame: containerView.bounds)
        sessions.append(session)
        switchToTab(sessions.count - 1)
        session.start(directory: directory)
        return session
    }

    func switchToTab(_ index: Int) {
        // Remove current terminal view from container
        activeSession?.terminalView.removeFromSuperview()

        activeSessionIndex = index

        // Add new terminal view to container
        if let session = activeSession {
            session.terminalView.frame = containerView.bounds
            containerView.addSubview(session.terminalView)
            containerView.window?.makeFirstResponder(session.terminalView)
        }
    }

    func closeTab(at index: Int) {
        let session = sessions[index]
        session.terminalView.removeFromSuperview()
        // Optionally send SIGHUP to the process
        sessions.remove(at: index)
        if activeSessionIndex >= sessions.count {
            activeSessionIndex = max(0, sessions.count - 1)
        }
        switchToTab(activeSessionIndex)
    }
}
```

**Reference project:** The [MenuBarTerminal](https://github.com/nexusprojekts/MenuBarTerminal) project uses SwiftTerm with a `TerminalTabView` that manages multiple terminal tabs, each with its own `TerminalViewController` instance.

### Critical: Sandbox Must Be Disabled

For `LocalProcessTerminalView` to work, you MUST disable App Sandbox in your target's "Signing and Capabilities". Without this, the spawned shell will not have access to the filesystem, commands, or most system resources.

### Drag-and-Drop File Paths into Terminal

To insert file paths when files are dragged onto the terminal, you register the terminal view for drag operations and insert escaped paths at the cursor position:

```swift
// Insert a shell-safe escaped path at the terminal cursor
func insertFilePath(_ path: String) {
    let escaped = path
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: " ", with: "\\ ")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\"", with: "\\\"")
    terminalView.send(txt: escaped)
}
```

### Performance Characteristics

SwiftTerm's architecture supports the performance targets in the project brief:
- PTY data is consumed via non-blocking reads
- The terminal view uses virtualized rendering (only visible cells are drawn)
- Escape sequence parsing is done in the `Terminal` engine off the main rendering path
- Font metrics are cached and reused across paints

---

## 2. Embedded Browser: Chromium vs WKWebView on macOS

### Summary of Options

| Approach | Engine | Complexity | App Store OK | Size Impact |
|----------|--------|-----------|-------------|-------------|
| **WKWebView (WebKit)** | WebKit (system) | Low | Yes | Minimal (uses OS component) |
| **CEF (Chromium Embedded Framework)** | Chromium/Blink | Very High | Difficult | +200-400 MB |
| **Electron wrapper** | Chromium/V8 | Medium | No (generally) | +150-300 MB |
| **Arc-style (Chromium + Swift UI)** | Chromium | Very High | No (direct dist.) | +200-400 MB |

### WKWebView -- The Standard Approach

WKWebView is the standard and recommended way to embed web content in a native macOS app.

**Advantages:**
- Ships with macOS, no additional binary size
- Optimized for Apple Silicon (M1/M2/M3)
- Battery efficient -- uses the system WebKit process
- App Store compatible
- Supports modern web standards (HTML5, CSS3, ES2023+)
- Safari Web Inspector integration via `isInspectable` property (macOS 13.3+)
- Integrates with macOS security model (sandboxing, Keychain)

**Limitations:**
- Cannot run Chrome extensions natively
- Rendering may differ from Chromium in edge cases
- No V8 engine (uses JavaScriptCore instead)
- Cannot customize the rendering engine internals

**Key API (macOS 13+):**
```swift
import WebKit

let config = WKWebViewConfiguration()
config.preferences.isElementFullscreenEnabled = true

let webView = WKWebView(frame: .zero, configuration: config)
webView.isInspectable = true  // Enable Safari Web Inspector
webView.load(URLRequest(url: URL(string: "https://example.com")!))
```

### CEF (Chromium Embedded Framework) -- The Complex Alternative

CEF is a C/C++ framework for embedding Chromium. It is technically possible on macOS but extremely complex.

**Key challenges:**
- CEF runs as TWO separate processes (Render + Browser) communicating via IPC
- Requires its own message pump that conflicts with the Mac app's NSApplication run loop
- Binary size adds 200-400 MB to your app
- Must coordinate sandboxing between CEF processes and your app
- GPU acceleration setup is complex
- No active, well-maintained Swift bindings (CEF.swift is stale, x86_64 only)

**Available Swift bindings:**
- [CEF.swift](https://github.com/lvsti/CEF.swift) -- macOS 10.9+, x86_64 only, NOT actively maintained
- [MacChromiumStoryboard](https://github.com/electromaggot/MacChromiumStoryboard) -- Demo project showing CEF in an Xcode storyboard

### What Real macOS Browser Apps Use

| App | Rendering Engine | UI Framework | Notes |
|-----|-----------------|-------------|-------|
| **Safari** | WebKit | AppKit | Apple's own browser |
| **SigmaOS** | WebKit (WKWebView) | SwiftUI (native) | Native macOS app, supports Chrome extensions despite using WebKit |
| **Arc** | Chromium | Swift + SwiftUI | Native Swift UI wrapping Chromium rendering engine |
| **Sizzy** | Chromium | Electron + React | Cross-platform via Electron |
| **Polypane** | Chromium | Electron | Cross-platform via Electron, Chromium 116 |
| **Sigma OS** | WebKit | SwiftUI | Optimized for Apple Silicon, battery efficient |

**Key insight:** SigmaOS proves that you can build a full-featured browser with WKWebView/WebKit AND still support Chrome extensions. Arc chose Chromium but wrapped it in a native Swift/SwiftUI UI layer. Most developer tools (Sizzy, Polypane) use Electron.

### Recommendation for Velocity File Manager

For a file manager's built-in file viewer / web preview, **WKWebView is the correct choice**:
- It is a file viewer, not a full browser -- you just need to render HTML/CSS
- Zero additional binary size
- Full App Store compatibility
- The built-in Web Inspector (`isInspectable = true`) provides sufficient dev tools
- Native macOS integration (appearance, scrolling, text selection)
- If you ever need to render markdown, HTML files, or web content in the preview module, WKWebView handles it

You would only need Chromium if you were building a full web browser with Chrome extension support, which is not in scope for a file manager.

---

## 3. Best Tab Bar Pattern for AppKit

### Overview of Approaches

| Approach | Used By | Horizontal | Vertical | Flexibility | Complexity |
|----------|---------|-----------|----------|------------|------------|
| **NSWindow native tabs** | Finder, TextEdit | Yes | No | Low | Very Low |
| **NSTabView / NSTabViewController** | System Preferences | Yes | No | Low | Low |
| **PSMTabBarControl** | iTerm2 (legacy) | Yes | Yes (left) | Medium | Medium |
| **MMTabBarView** | (PSMTabBarControl successor) | Yes | Yes | Medium | Medium |
| **Bonsplit** | (new library) | Yes | No (but splits) | High | Medium |
| **Custom NSView** | Warp, Nova, VS Code (Electron) | Yes | Yes | Maximum | High |

### Approach 1: NSWindow Native Tabs (Simplest)

macOS Sierra (10.12+) introduced native window tabbing. This gives you Safari-style tabs for free.

```swift
// Enable native window tabbing
window.tabbingMode = .preferred
window.tabbingIdentifier = "com.velocity.terminal"

// Add a new tab
let newWindow = NSWindow(contentViewController: newTerminalVC)
window.addTabbedWindow(newWindow, ordered: .above)

// Handle the "+" button
override func newWindowForTab(_ sender: Any?) {
    let newWindow = createTerminalWindow()
    self.window?.addTabbedWindow(newWindow, ordered: .above)
    newWindow.makeKeyAndOrderFront(sender)
}
```

**Pros:** Zero custom UI code, native look and feel, drag-and-drop between windows, system animations.
**Cons:** Horizontal only, minimal customization, each tab is a full NSWindow, no vertical tab support, no control over tab appearance.

### Approach 2: NSTabView / NSTabViewController

The standard AppKit tab view. Used by System Preferences and similar apps.

```swift
let tabViewController = NSTabViewController()
tabViewController.tabStyle = .toolbar  // or .segmentedControlOnTop, .unspecified

let tab1 = NSTabViewItem(viewController: terminalVC1)
tab1.label = "Terminal 1"
tabViewController.addTabViewItem(tab1)
```

**Pros:** Built-in, simple API, works with storyboards.
**Cons:** Limited visual customization, no vertical orientation, looks like a settings panel (not a terminal tab bar), no drag reordering, no close buttons on tabs.

### Approach 3: PSMTabBarControl (iTerm2's Choice)

The classic open-source tab bar used by iTerm2 and many other macOS apps for years. Wraps `NSTabView` with a browser-style tab bar.

**Used by:** iTerm2 (as `ThirdParty/PSMTabBarControl`)

**Key features:**
- Safari-style tabs with close buttons
- Multiple visual styles (Metal, Aqua, Unified)
- Tab overflow with menu
- Drag-and-drop reordering
- iTerm2 supports top, bottom, and LEFT tab bar placement via PSMTabBarControl

**Source:** [GitLab - iTerm2 PSMTabBarControl](https://gitlab.com/gnachman/iterm2/-/tree/master/ThirdParty/PSMTabBarControl/source)

**Limitation:** Written in Objective-C, aging codebase. Works but requires bridging header for Swift projects.

### Approach 4: MMTabBarView (Modern PSMTabBarControl)

A modernized, view-based rewrite of PSMTabBarControl. BSD licensed.

**Key improvements over PSMTabBarControl:**
- View-based (not cell-based) architecture
- macOS 10.10+ support
- Xcode 9.3+ compatibility
- Objective-C with modern patterns
- Deprecated PSMTabBarControl delegate methods included for easy migration

**Source:** [GitHub - MiMo42/MMTabBarView](https://github.com/MiMo42/MMTabBarView)

**Limitation:** Still Objective-C. Not actively maintained in recent years.

### Approach 5: Bonsplit (Modern SwiftUI Library)

A new SwiftUI-native library for macOS that provides tabs AND split panes. Most relevant for a file manager / terminal app.

**Version:** 1.1.1
**SPM:** `https://github.com/almonk/bonsplit.git`

```swift
.package(url: "https://github.com/almonk/bonsplit.git", from: "1.1.1")
```

**Key features:**
- 120fps animations
- Drag-and-drop tab reordering
- Keyboard navigation
- Split panes (horizontal AND vertical)
- Cross-pane tab movement
- Dirty state indicators on tabs
- Configurable: min/max tab width, tab bar height, animation duration
- Delegate protocol for all events (tab create/close/select, pane split/close/focus)
- Content lifecycle: `.recreateOnSwitch` (low memory) or `.keepAllAlive` (maintains state)

**Configuration options:**
```swift
BonsplitConfiguration(
    allowSplits: true,
    allowCloseTabs: true,
    allowCloseLastPane: false,
    allowTabReordering: true,
    allowCrossPaneTabMove: true,
    autoCloseEmptyPanes: true,
    tabBarHeight: 33,
    tabMinWidth: 140,
    tabMaxWidth: 220,
    minimumPaneWidth: 100,
    minimumPaneHeight: 100,
    showSplitButtons: true,
    animationDuration: 0.15
)
```

**Tab operations:**
```swift
controller.createTab(title: "Terminal", icon: "terminal", isDirty: false, inPane: paneId)
controller.updateTab(tabId, isDirty: true)
controller.updateTab(tabId, title: "New Title")
controller.closeTab(tabId)
controller.selectTab(tabId)
controller.selectPreviousTab()
controller.selectNextTab()
```

**Split operations:**
```swift
controller.splitPane(orientation: .horizontal)
controller.splitPane(orientation: .vertical, withTab: Tab(title: "New", icon: "doc"))
```

**Limitation:** SwiftUI only (not AppKit). For an AppKit-primary app, you would need to host Bonsplit in an `NSHostingView`.

### Approach 6: Fully Custom NSView Tab Bar (Maximum Control)

This is what production apps like Warp, Nova, and most serious macOS apps ultimately use. You build the tab bar as a custom `NSView` (or `NSStackView`) with custom tab item views.

**Architecture pattern:**
```
TabBarView (NSView or NSStackView)
  +-- TabItemView (NSView) -- one per tab
  |     +-- icon (NSImageView)
  |     +-- title (NSTextField)
  |     +-- close button (NSButton)
  |     +-- dirty indicator (NSView)
  +-- "+" button (NSButton)
```

**Why custom is often the right choice for a power-user app:**
- Full control over rendering (pixel-perfect design)
- Both horizontal AND vertical orientation (just change the stack axis)
- Custom drag-and-drop behavior (between tabs, between panes, from Finder)
- Custom context menus per tab
- Animations exactly as desired
- Performance: can use Core Animation layers for 60fps tab transitions
- Accessibility: full VoiceOver control
- No dependency on third-party code

**Horizontal-to-vertical switching with NSStackView:**
```swift
class FlexibleTabBar: NSStackView {
    enum Orientation { case horizontal, vertical }

    var tabOrientation: Orientation = .horizontal {
        didSet {
            self.orientation = (tabOrientation == .horizontal)
                ? .horizontal : .vertical
            // Adjust tab item layout accordingly
            for case let tabView as TabItemView in arrangedSubviews {
                tabView.updateLayout(for: tabOrientation)
            }
        }
    }
}
```

### What Professional macOS Apps Actually Use

| App | Tab Implementation | Vertical Tabs | Notes |
|-----|-------------------|--------------|-------|
| **Terminal.app** | NSWindow native tabs | No | System standard |
| **iTerm2** | PSMTabBarControl (custom fork) | Yes (left sidebar) | Supports top, bottom, left placement |
| **Safari** | NSWindow native tabs + custom | No | Compact/separate modes |
| **Nova (Panic)** | Custom NSView | Yes (sidebar) | Full custom implementation |
| **Warp** | Custom (Rust + Metal rendered) | No (requested feature) | Completely custom rendering |
| **VS Code** | Electron/DOM | Yes | Not native |
| **Xcode** | Custom NSView | No | Navigators are a sidebar, not vertical tabs |

### Recommendation for Velocity File Manager

**For maximum flexibility, build a custom NSView-based tab bar.** Here is the rationale:

1. **Velocity needs both horizontal and vertical tabs** -- Only custom or PSMTabBarControl/MMTabBarView support this. Bonsplit supports splits but not vertical tab bars.

2. **Terminal tabs need custom behavior** -- dirty indicators, process status, drag-and-drop file paths, terminal title from escape sequences, context menus with "Duplicate Tab", "Move to Split", etc.

3. **Dual-pane file browser tabs are different from terminal tabs** -- You likely need different tab bar styles for file browser tabs vs. terminal tabs. A custom solution lets you share the core tab bar component but vary the visual style.

4. **Performance** -- A custom `NSView` with Core Animation layers will meet the <16ms render target. No SwiftUI bridging overhead.

5. **If you want to move faster initially**, consider using **Bonsplit** hosted in `NSHostingView` for the terminal module, since it already handles tabs + splits. Then migrate to a fully custom solution if you hit limitations.

---

## Sources

### SwiftTerm
- [SwiftTerm GitHub Repository](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm Releases](https://github.com/migueldeicaza/SwiftTerm/releases)
- [SwiftTerm -- Swift Package Index](https://swiftpackageindex.com/migueldeicaza/SwiftTerm)
- [SwiftTerm-Example (ajhekman)](https://github.com/ajhekman/SwiftTerm-Example)
- [MenuBarTerminal (multi-tab SwiftTerm example)](https://github.com/nexusprojekts/MenuBarTerminal)
- [LocalProcess.swift source](https://raw.githubusercontent.com/migueldeicaza/SwiftTerm/main/Sources/SwiftTerm/LocalProcess.swift)
- [MacTerminalView.swift source](https://raw.githubusercontent.com/migueldeicaza/SwiftTerm/main/Sources/SwiftTerm/Mac/MacTerminalView.swift)
- [AppleTerminalView.swift source](https://raw.githubusercontent.com/migueldeicaza/SwiftTerm/main/Sources/SwiftTerm/Apple/AppleTerminalView.swift)

### Embedded Browser / Chromium
- [CEF.swift -- Swift bindings for CEF](https://github.com/lvsti/CEF.swift)
- [MacChromiumStoryboard -- CEF in Xcode demo](https://github.com/electromaggot/MacChromiumStoryboard)
- [Chromium Embedded Framework (CEF)](https://github.com/chromiumembedded/cef)
- [Apple Developer Forums -- Chrome/Chromium in Swift](https://developer.apple.com/forums/thread/128615)
- [SigmaOS -- Native WebKit browser](https://sigmaos.com/)
- [Arc Browser -- Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))
- [WKWebView isInspectable -- WebKit Blog](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)

### Tab Bars
- [Bonsplit -- macOS tab bar + split pane library](https://github.com/almonk/bonsplit)
- [Bonsplit Documentation](https://bonsplit.alasdairmonk.com/)
- [PSMTabBarControl (iTerm2 fork)](https://gitlab.com/gnachman/iterm2/-/tree/master/ThirdParty/PSMTabBarControl/source)
- [MMTabBarView -- Modern PSMTabBarControl rewrite](https://github.com/MiMo42/MMTabBarView)
- [NSWindow.tabbingMode -- Apple Documentation](https://developer.apple.com/documentation/appkit/nswindow/1644729-tabbingmode)
- [NSTabViewController -- Apple Documentation](https://developer.apple.com/documentation/appkit/nstabviewcontroller)
- [Programmatically Add Tabs to NSWindows](https://christiantietze.de/posts/2019/01/programmatically-add-nswindow-tabs/)
- [iTerm2 Appearance Preferences](https://iterm2.com/documentation-preferences-appearance.html)
