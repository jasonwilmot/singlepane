// FileTemplate.swift
// Defines predefined file templates for quick file creation.
// Each template specifies an extension, default filename, initial content,
// and whether executable permissions should be set after creation.

import Foundation
import UniformTypeIdentifiers

struct FileTemplate: Sendable {

    /// File extension (e.g., "md", "txt").
    let fileExtension: String

    /// Default filename without extension (e.g., "untitled").
    let baseName: String

    /// Initial file content written on creation.
    let defaultContent: String

    /// Whether to set the executable bit (0o755) after creation.
    let needsExecutablePermission: Bool

    /// Full default filename (e.g., "untitled.md").
    var defaultFilename: String { "\(baseName).\(fileExtension)" }

    /// The UTType for this template's file extension, used for icon lookup.
    var utType: UTType? { UTType(filenameExtension: fileExtension) }
}

// MARK: - Built-in Templates

extension FileTemplate {

    /// Predefined developer file templates for quick creation.
    static let builtIn: [FileTemplate] = [
        FileTemplate(
            fileExtension: "md",
            baseName: "untitled",
            defaultContent: "# untitled\n",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "txt",
            baseName: "untitled",
            defaultContent: "",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "json",
            baseName: "untitled",
            defaultContent: "{}\n",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "yaml",
            baseName: "untitled",
            defaultContent: "",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "swift",
            baseName: "untitled",
            defaultContent: "import Foundation\n",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "py",
            baseName: "untitled",
            defaultContent: "",
            needsExecutablePermission: false
        ),
        FileTemplate(
            fileExtension: "sh",
            baseName: "untitled",
            defaultContent: "#!/bin/bash\n",
            needsExecutablePermission: true
        ),
    ]
}
