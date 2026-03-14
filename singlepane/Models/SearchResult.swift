// SearchResult.swift
// Lightweight, Sendable value type representing a single search match.
// Wraps a FileItem with additional search-specific metadata (excerpt, line number).

import Foundation

struct SearchResult: Identifiable, Sendable {
    /// Unique identity is the file path combined with match line for deduplication.
    var id: String { fileItem.path + ":\(matchLine ?? 0)" }

    /// The matched file system entry.
    let fileItem: FileItem

    /// Excerpt of the matching content line (content search mode only).
    let matchExcerpt: String?

    /// 1-based line number where the match occurred (content search mode only).
    let matchLine: Int?

    /// Full absolute path to the file — convenience accessor for display.
    var fullPath: String { fileItem.path }
}

// MARK: - Search Types

/// Determines whether search matches against filenames or file contents.
enum SearchMode: Sendable {
    case filename
    case content
}

/// Toggleable options that modify search behavior.
struct SearchOptions: Sendable, Equatable {
    var caseSensitive: Bool = false
    var regex: Bool = false
}
