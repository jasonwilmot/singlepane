// FileItem.swift
// Lightweight, Sendable value type representing a single file system entry.
// Used across threads safely via actor-isolated FileService.

import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Sendable {
    /// Unique identity is the file URL.
    var id: URL { url }

    let name: String

    /// Raw absolute path string. Stored instead of URL to avoid the cost of
    /// `URL(fileURLWithPath:)` in hot loops — URL is computed lazily on access.
    let path: String

    let size: Int64
    let dateModified: Date
    let isDirectory: Bool
    let isHidden: Bool
    let fileType: UTType?

    /// File URL computed from the stored path. Created on demand rather than
    /// eagerly during search/enumeration to avoid per-entry filesystem checks.
    var url: URL { URL(fileURLWithPath: path) }
}
