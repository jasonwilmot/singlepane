// ObservableTerminalView.swift
// Thin subclass of LocalProcessTerminalView that exposes SwiftTerm's
// scroll and buffer-change callbacks as a single closure.
// Used to drive immediate link overlay invalidation — the base class
// implements scrolled() and rangeChanged() as no-ops, so we override
// them here to notify the terminal container when content changes.

import AppKit
import SwiftTerm

@MainActor
final class ObservableTerminalView: LocalProcessTerminalView {

    // MARK: - Content Change Callback

    /// Called whenever the visible terminal content changes — scroll, new output,
    /// screen clear, etc. Set by the terminal container to clear stale link
    /// underlines and schedule a debounced rescan.
    var onContentChanged: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Enable rangeChanged callbacks — disabled by default in SwiftTerm.
        notifyUpdateChanges = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - SwiftTerm Overrides

    /// Called when the terminal viewport scrolls (user scroll or new output pushing content up).
    override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        onContentChanged?()
    }

    /// Called when terminal buffer content changes visually (new output, screen clear, reflow).
    /// Only fires when `notifyUpdateChanges` is true.
    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        onContentChanged?()
    }
}
