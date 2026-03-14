// TerminalSession.swift
// Wraps a single SwiftTerm LocalProcessTerminalView with session metadata.
// Each tab in the terminal panel owns one TerminalSession.

import AppKit
import SwiftTerm

@MainActor
final class TerminalSession {

    // MARK: - Properties

    let id: UUID = UUID()
    let terminalView: LocalProcessTerminalView
    var title: String

    /// Hook-driven highlight color for this session's tab.
    /// Stored on the session so it survives focus/repaint cycles.
    var hookHighlightColor: NSColor?

    /// Persisted search text for this session — saved/restored when switching tabs.
    var searchText: String = ""

    /// 1-based index of the current match within the total count.
    var currentMatchIndex: Int = 0

    /// User-assigned custom tab title. When set, overrides the auto-generated
    /// directory name. Cleared (nil) to revert to the default CWD-based title.
    /// Not persisted across app restarts.
    var customTabTitle: String?

    /// Current working directory reported by the shell via OSC 7.
    /// Used to resolve relative file paths for click-to-open link detection.
    var currentDirectory: String?

    /// OSC 133 command marks — tracks prompt/command/output boundaries.
    /// Ordered by absolute line number (appended chronologically).
    private(set) var commandMarks: [CommandMark] = []

    /// Called when the shell starts executing a command (OSC 133 B).
    var onCommandStarted: (() -> Void)?

    /// Called when the shell finishes a command (OSC 133 D).
    var onCommandFinished: (() -> Void)?

    // MARK: - Init

    init(frame: NSRect) {
        self.title = "Terminal"
        self.terminalView = LocalProcessTerminalView(frame: frame)
        self.terminalView.autoresizingMask = [.width, .height]
        configureAppearance()
    }

    // MARK: - Configuration

    private func configureAppearance() {
        terminalView.optionAsMetaKey = true
        configureScrollerStyle()
        applyTheme()
        applyFont()
    }

    /// Removes the SwiftTerm scrollbar entirely — no scrollbar, like Ghostty.
    /// The scroller is a private property on MacTerminalView, so we locate it via recursive
    /// subview traversal — the NSScrollView may be nested.
    /// Called at init and again after the view enters the hierarchy (subviews may not exist at init).
    func configureScrollerStyle() {
        func removeScroller(in view: NSView) -> Bool {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView {
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                    return true
                }
                if let scroller = subview as? NSScroller {
                    scroller.isHidden = true
                    scroller.removeFromSuperview()
                    return true
                }
                if removeScroller(in: subview) {
                    return true
                }
            }
            return false
        }
        _ = removeScroller(in: terminalView)
    }

    /// Applies the active font to this terminal view.
    /// Called on init and when the global font changes.
    func applyFont() {
        terminalView.font = FontManager.shared.activeFont
    }

    /// Applies the active theme's colors to this terminal view.
    /// Called on init and when the global theme changes.
    func applyTheme() {
        let theme = ThemeManager.shared.activeTheme

        // Terminal foreground/background
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.nativeBackgroundColor = theme.backgroundColor

        // Cursor color
        terminalView.caretColor = theme.cursorColor

        // 16-color ANSI palette — convert NSColor → SwiftTerm Color (UInt16 RGB)
        let ansiColors: [Color] = (0..<16).map { index in
            let nsColor = theme.paletteColor(at: index)
            guard let rgb = nsColor.usingColorSpace(.sRGB) else {
                return Color(red: 0, green: 0, blue: 0)
            }
            return Color(
                red: UInt16(rgb.redComponent * 65535),
                green: UInt16(rgb.greenComponent * 65535),
                blue: UInt16(rgb.blueComponent * 65535)
            )
        }
        terminalView.installColors(ansiColors)
    }

    // MARK: - Command Marks (OSC 133)

    /// Appends a new command mark at the given absolute line.
    /// Lazily prunes marks that have scrolled out of the buffer on each insert.
    func addCommandMark(type: CommandMarkType, absoluteLine: Int, exitCode: Int? = nil) {
        // Prune marks that are no longer reachable in the scrollback.
        // When the circular buffer trims old lines, marks with absolute lines
        // below yDisp=0's equivalent become stale. We detect this by checking
        // if a mark's line is negative relative to any reachable scroll position.
        // In practice: remove marks more than (lines.count) behind the current line.
        let maxScrollback = max(absoluteLine - terminalView.getTerminal().rows, 0)
        if !commandMarks.isEmpty, let firstLine = commandMarks.first?.absoluteLine {
            if firstLine < maxScrollback - terminalView.getTerminal().rows * 10 {
                // Trim marks that are far behind — keep a generous buffer so
                // marks near the scrollback boundary aren't prematurely removed.
                commandMarks.removeAll { $0.absoluteLine < maxScrollback }
            }
        }

        let mark = CommandMark(absoluteLine: absoluteLine, type: type, exitCode: exitCode)
        commandMarks.append(mark)
    }

    /// Returns the nearest `.promptStart` mark above the given line, or nil.
    func promptMarkAbove(line: Int) -> CommandMark? {
        commandMarks.last { $0.type == .promptStart && $0.absoluteLine < line }
    }

    /// Returns the nearest `.promptStart` mark at or below the given line, or nil.
    func promptMarkBelow(line: Int) -> CommandMark? {
        commandMarks.first { $0.type == .promptStart && $0.absoluteLine > line }
    }

    /// Returns the exit code for the command that started at or near the given prompt line.
    /// Searches forward from `promptLine` for the next `.commandFinished` mark.
    func exitCode(forPromptAt promptLine: Int) -> Int? {
        commandMarks.first {
            $0.type == .commandFinished && $0.absoluteLine > promptLine
        }?.exitCode
    }

    // MARK: - Process Management

    /// Start the user's login shell. Reads $SHELL, defaults to /bin/zsh.
    /// Injects SP_TAB_ID=<session UUID> so external tools (e.g. Claude Code hooks)
    /// can target this specific tab via the singlepane:// URL scheme.
    /// Sources the bundled OSC 133 shell integration script for command mark support.
    func startShell(currentDirectory: String? = nil) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd = currentDirectory ?? NSHomeDirectory()

        // Set the initial CWD immediately so link detection can resolve
        // relative paths before the shell's first OSC 7 report arrives.
        self.currentDirectory = cwd

        // Build environment: SwiftTerm defaults + our session identifier.
        // TERM_PROGRAM=Apple_Terminal activates macOS's built-in OSC 7 hook
        // (/etc/zshrc_Apple_Terminal) so zsh reports CWD changes to the terminal.
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("SP_TAB_ID=\(id.uuidString)")
        env.append("TC_TAB_ID=\(id.uuidString)")
        env.append("TERM_PROGRAM=Apple_Terminal")
        env.append("COLORTERM=truecolor")

        // Resolve the bundled shell integration script for OSC 133 command marks.
        // Set VELOCITY_SHELL_INTEGRATION so the script path is available to the shell.
        let shellName = (shell as NSString).lastPathComponent
        if let scriptPath = Self.shellIntegrationPath(for: shellName) {
            env.append("VELOCITY_SHELL_INTEGRATION=\(scriptPath)")
        }

        // Inject the integration script into the shell startup chain.
        // - zsh: Create a temporary ZDOTDIR with a .zshrc that sources the
        //   integration script then sources the user's real .zshrc. This
        //   ensures our hooks load after all profile/rc files have run.
        // - bash: Set BASH_ENV to the integration script path so it's sourced
        //   for interactive login shells.
        let args: [String]
        switch shellName {
        case "zsh":
            if let scriptPath = Self.shellIntegrationPath(for: shellName) {
                Self.setupZshIntegration(env: &env, scriptPath: scriptPath)
            }
            args = ["-l"]
        case "bash":
            // For bash, inject sourcing via PROMPT_COMMAND. This runs before
            // the first prompt and self-removes after loading. Works with
            // both login and interactive shells without conflicting with -l.
            if let scriptPath = Self.shellIntegrationPath(for: shellName) {
                Self.setupBashIntegration(env: &env, scriptPath: scriptPath)
            }
            args = ["-l"]
        default:
            args = ["-l"]
        }

        // Launch as a login shell so the full profile chain runs (.zprofile, .zshrc, etc.)
        // and PATH matches what the user sees in their regular terminal app.
        // Prefixing execName with "-" is the POSIX convention for login shells.
        terminalView.startProcess(
            executable: shell,
            args: args,
            environment: env,
            execName: "-\(shellName)",
            currentDirectory: cwd
        )

        // Register the OSC 133 handler after the terminal is started.
        installOSC133Handler()
    }

    // MARK: - Shell Integration

    /// Creates a temporary ZDOTDIR with a .zshrc that sources our integration script
    /// then chains to the user's real .zshrc. This is the same technique VS Code uses.
    /// The temporary directory persists for the session's lifetime.
    private static func setupZshIntegration(env: inout [String], scriptPath: String) {
        let tmpDir = NSTemporaryDirectory() + "velocity-zsh-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        // Save the user's original ZDOTDIR so the .zshrc can restore it.
        let userZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        env.append("VELOCITY_ORIGINAL_ZDOTDIR=\(userZdotdir)")

        // Write a .zshrc that:
        //   1. Restores ZDOTDIR to the user's real value
        //   2. Sources the user's real .zshrc
        //   3. Sources our integration script (after .zshrc so hooks fire last)
        let zshrc = """
        # Velocity shell integration bootstrap — restores user config then loads OSC 133 hooks.
        export ZDOTDIR="$VELOCITY_ORIGINAL_ZDOTDIR"
        [[ -f "$ZDOTDIR/.zshrc" ]] && source "$ZDOTDIR/.zshrc"
        source '\(scriptPath)'
        """
        try? zshrc.write(toFile: tmpDir + "/.zshrc", atomically: true, encoding: .utf8)

        // Chain .zshenv and .zprofile to the user's real files.
        // IMPORTANT: Do NOT restore ZDOTDIR here — zsh re-evaluates ZDOTDIR
        // between startup files (.zshenv → .zprofile → .zshrc). If we restore
        // it in .zshenv, zsh will look for .zshrc in the user's home instead
        // of our temp dir, and our integration script never loads.
        let zshenv = """
        [[ -f "$VELOCITY_ORIGINAL_ZDOTDIR/.zshenv" ]] && source "$VELOCITY_ORIGINAL_ZDOTDIR/.zshenv"
        """
        try? zshenv.write(toFile: tmpDir + "/.zshenv", atomically: true, encoding: .utf8)

        let zprofile = """
        [[ -f "$VELOCITY_ORIGINAL_ZDOTDIR/.zprofile" ]] && source "$VELOCITY_ORIGINAL_ZDOTDIR/.zprofile"
        """
        try? zprofile.write(toFile: tmpDir + "/.zprofile", atomically: true, encoding: .utf8)

        env.append("ZDOTDIR=\(tmpDir)")
    }

    /// Injects the bash integration script by prepending a one-shot source command
    /// to PROMPT_COMMAND. The injected command sources the script then removes itself,
    /// so the user's PROMPT_COMMAND is restored cleanly after the first prompt.
    private static func setupBashIntegration(env: inout [String], scriptPath: String) {
        // Prepend a self-removing source command to PROMPT_COMMAND.
        // After sourcing, the integration script's own __velocity_prompt_command
        // takes over and this bootstrap entry is no longer needed.
        let bootstrap = "source '\(scriptPath)'"
        let existingPC = ProcessInfo.processInfo.environment["PROMPT_COMMAND"] ?? ""
        if existingPC.isEmpty {
            env.append("PROMPT_COMMAND=\(bootstrap)")
        } else {
            env.append("PROMPT_COMMAND=\(bootstrap);\(existingPC)")
        }
    }

    /// Returns the path to the bundled shell integration script for the given shell.
    private static func shellIntegrationPath(for shellName: String) -> String? {
        let scriptName: String
        switch shellName {
        case "zsh":  scriptName = "velocity-integration.zsh"
        case "bash": scriptName = "velocity-integration.bash"
        default:     return nil
        }
        // Try subdirectory first (preserved folder reference), then flat (copy resources).
        return Bundle.main.path(forResource: scriptName, ofType: nil, inDirectory: "ShellIntegration")
            ?? Bundle.main.path(forResource: scriptName, ofType: nil)
    }

    /// Registers an OSC 133 handler on the SwiftTerm parser.
    /// Intercepts prompt/command boundary sequences and stores them as CommandMarks.
    private func installOSC133Handler() {
        let terminal = terminalView.getTerminal()
        terminal.parser.oscHandlers[133] = { [weak self] data in
            guard let self else { return }

            // Payload format: "A", "B", "C", or "D;exitcode"
            guard let payload = String(bytes: data, encoding: .utf8),
                  let markChar = payload.first else { return }

            // Compute the absolute line in the buffer. When OSC 133 fires, the
            // shell is actively writing output — the terminal is always scrolled to
            // the bottom, so yDisp == yBase. Using yDisp (public) avoids accessing
            // yBase (internal to SwiftTerm).
            let buffer = terminal.buffer
            let absoluteLine = buffer.y + buffer.yDisp

            switch markChar {
            case "A":
                self.addCommandMark(type: .promptStart, absoluteLine: absoluteLine)
            case "B":
                self.addCommandMark(type: .commandStart, absoluteLine: absoluteLine)
                Task { @MainActor in self.onCommandStarted?() }
            case "C":
                self.addCommandMark(type: .outputStart, absoluteLine: absoluteLine)
            case "D":
                // Parse exit code from "D;exitcode" format.
                let exitCode: Int?
                if payload.count > 2 {
                    let codeStr = payload.dropFirst(2) // Drop "D;"
                    exitCode = Int(codeStr)
                } else {
                    exitCode = nil
                }
                self.addCommandMark(type: .commandFinished, absoluteLine: absoluteLine, exitCode: exitCode)
                Task { @MainActor in self.onCommandFinished?() }
            default:
                break
            }
        }
    }
}
