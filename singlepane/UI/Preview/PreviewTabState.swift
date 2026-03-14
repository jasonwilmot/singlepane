// PreviewTabState.swift
// Per-tab state for the multi-file preview panel.
// Each open file tab maintains its own independent state — file URL, mode,
// scroll position, cursor position, dirty text, and file type flags.
// Shared child VCs (editor, preview, etc.) save/restore from these states
// on tab switch, avoiding the cost of one VC set per tab.

import AppKit

/// State snapshot for a single file tab in the preview panel.
@MainActor
final class PreviewTabState {

    /// The file this tab represents.
    var fileURL: URL

    /// Current preview/edit mode for this tab.
    var mode: PreviewTabMode = .preview

    /// Whether this file supports rendered preview (markdown, HTML).
    var hasPreviewSupport: Bool = false

    /// Whether this file is markdown (controls outline visibility).
    var isMarkdownFile: Bool = false

    /// Whether the code preview VC is used instead of the markdown preview.
    var useCodePreview: Bool = false

    /// Whether the user explicitly chose editor mode for a previewable file.
    var userChoseEditor: Bool = false

    /// Whether the editor has unsaved changes.
    var hasUnsavedChanges: Bool = false

    /// Dirty text from the editor — preserved across tab switches.
    /// Nil when the file hasn't been edited or was saved.
    var dirtyText: String?

    /// Editor cursor position (character offset) for restore.
    var editorCursorPosition: Int = 0

    /// Editor scroll position (content offset Y) for restore.
    var editorScrollY: CGFloat = 0

    /// Code preview scroll position for restore.
    var codePreviewScrollY: CGFloat = 0

    /// Markdown/HTML preview scroll position for restore.
    /// Stored as a fractional value (0.0–1.0) since WKWebView scroll
    /// positions are retrieved asynchronously via JavaScript.
    var webViewScrollFraction: CGFloat = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

/// The two display modes available per preview tab.
enum PreviewTabMode: Int {
    case preview = 0
    case editor = 1
}
