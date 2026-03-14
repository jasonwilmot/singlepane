// TextFileDetection.swift
// Shared utility for fast text file detection by extension.
// Consolidated from SearchService and IndexService to avoid duplicate heap allocations.

import Foundation
import UniformTypeIdentifiers

enum TextFileDetection {

    // MARK: - Static Constants

    /// Known text file extensions — allocated once, shared across all callers.
    /// Superset of extensions from SearchService and IndexService.
    static let textExtensions: Set<String> = [
        // Prose / docs
        "txt", "md", "markdown",
        // Web
        "html", "htm", "css", "scss", "less", "json", "xml", "yaml", "yml",
        // Config
        "toml", "ini", "cfg", "conf", "env",
        // Shell
        "sh", "bash", "zsh", "fish",
        // Swift / Apple
        "swift", "m", "mm",
        // C family
        "c", "cpp", "h", "hpp",
        // JVM
        "java", "kt", "scala", "clj", "gradle",
        // Go / Rust
        "go", "rs",
        // Scripting
        "py", "rb", "lua", "r", "R", "vim",
        // JS / TS
        "js", "ts", "jsx", "tsx",
        // Erlang / Elixir
        "ex", "exs", "erl",
        // Data
        "sql", "graphql", "proto", "csv", "tsv", "log",
        // Build / CI
        "dockerfile", "makefile", "cmake",
        // Git
        "gitignore", "gitattributes"
    ]

    /// Extensionless filenames known to be text (e.g., Makefile, Dockerfile).
    static let textFilenames: Set<String> = [
        "Makefile", "Dockerfile", "Rakefile", "Gemfile",
        "Podfile", "Fastfile", "Brewfile", "Procfile",
        ".gitignore", ".gitattributes", ".env"
    ]

    // MARK: - Detection

    /// Returns true if the file is likely a text file based on its name.
    /// Fast path: checks extension against the static set.
    /// Slow path: falls back to UTType conformance for unknown extensions.
    static func isText(name: String) -> Bool {
        let ext = name.pathExtensionFast.lowercased()

        // Fast path: known extension
        if textExtensions.contains(ext) { return true }

        // Extensionless files — check known filenames
        if ext.isEmpty {
            if textFilenames.contains(name) { return true }

            // UTType fallback for files with no extension
            if let utType = UTType(filenameExtension: "") {
                return utType.conforms(to: .text) || utType.conforms(to: .sourceCode)
            }
            return false
        }

        // Unknown extension — UTType fallback
        if let utType = UTType(filenameExtension: ext) {
            return utType.conforms(to: .text) || utType.conforms(to: .sourceCode)
        }

        return false
    }
}

// MARK: - String Path Helpers

extension String {

    /// Extracts the file extension without NSString bridging.
    /// Returns empty string if no extension is found.
    var pathExtensionFast: String {
        guard let dotIndex = self.lastIndex(of: ".") else { return "" }
        let afterDot = self.index(after: dotIndex)
        guard afterDot < self.endIndex else { return "" }
        // Ensure the dot isn't part of a hidden file prefix (e.g., ".gitignore")
        if dotIndex == self.startIndex { return "" }
        return String(self[afterDot...])
    }

    /// Returns the parent path by slicing at the last `/`.
    /// Avoids NSString bridging overhead in hot loops.
    var parentPathFast: String {
        guard let slashIndex = self.lastIndex(of: "/") else { return self }
        if slashIndex == self.startIndex { return "/" }
        return String(self[self.startIndex..<slashIndex])
    }
}
