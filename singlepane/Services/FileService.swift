// FileService.swift
// Actor-isolated file service. All file system access runs off the main thread.
// Wraps DirectoryEnumerator for safe concurrent access.

import Foundation

actor FileService {

    /// List the contents of a directory. Runs on the actor's executor (off main thread).
    func listDirectory(at url: URL) throws -> [FileItem] {
        try DirectoryEnumerator.enumerate(at: url)
    }

    /// Returns sorted directory names (subdirectories only) within the given parent URL.
    /// Used by breadcrumb segment dropdowns to show sibling directories.
    func subdirectories(of url: URL) -> [String] {
        let path = url.path
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { namePtr in
                namePtr.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(entry.pointee.d_namlen)
                ) { ptr in
                    String(cString: ptr)
                }
            }
            if name == "." || name == ".." { continue }

            // Check if this entry is a directory
            let fullPath = (path as NSString).appendingPathComponent(name)
            var statBuf = stat()
            guard lstat(fullPath, &statBuf) == 0,
                  (statBuf.st_mode & S_IFMT) == S_IFDIR else { continue }

            names.append(name)
        }

        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Returns sorted directory names matching a given prefix within the parent URL.
    /// Used by breadcrumb edit mode for path autocomplete.
    func matchingSubdirectories(of url: URL, prefix: String) -> [String] {
        let lowercasePrefix = prefix.lowercased()
        return subdirectories(of: url).filter {
            $0.lowercased().hasPrefix(lowercasePrefix)
        }
    }

    // MARK: - Folder Creation

    /// Creates a new folder in the given directory named "untitled".
    /// Auto-increments if a collision exists (untitled → untitled 2 → untitled 3).
    /// Returns the URL of the created folder.
    @discardableResult
    func createFolder(in directory: URL) throws -> URL {
        let name = availableFolderName(in: directory, baseName: "untitled")
        let folderURL = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    // MARK: - File Creation

    /// Creates a new file in the given directory from a template.
    /// Auto-increments the filename if a collision exists (untitled.md → untitled 2.md).
    /// Returns the URL of the created file.
    @discardableResult
    func createFile(in directory: URL, template: FileTemplate) throws -> URL {
        let filename = availableFilename(
            in: directory,
            baseName: template.baseName,
            extension: template.fileExtension
        )
        let fileURL = directory.appendingPathComponent(filename)
        let data = template.defaultContent.data(using: .utf8) ?? Data()

        guard FileManager.default.createFile(atPath: fileURL.path, contents: data) else {
            throw FileOperationError.createFailed(fileURL)
        }

        if template.needsExecutablePermission {
            try setExecutablePermission(at: fileURL)
        }

        return fileURL
    }

    /// Renames a file by moving it from one URL to another within the same directory.
    func renameFile(from sourceURL: URL, to newName: String) throws -> URL {
        let destinationURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(newName)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Moves a file or directory to the Trash. Safe and undoable via Finder.
    func trashFile(at url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Duplicates a file in the same directory with a " copy" suffix.
    /// Auto-increments if "name copy.ext" already exists ("name copy 2.ext", etc.).
    /// Returns the URL of the duplicated file.
    @discardableResult
    func duplicateFile(at url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let nameWithoutExt = (url.lastPathComponent as NSString).deletingPathExtension
        let baseName = "\(nameWithoutExt) copy"
        let filename = availableFilename(in: directory, baseName: baseName, extension: ext)
        let destinationURL = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    /// Pastes (copies) files from the given URLs into the destination directory.
    /// Handles name conflicts by appending " copy" / " copy 2" etc.
    func pasteFiles(_ sourceURLs: [URL], into destinationDirectory: URL) throws {
        let fm = FileManager.default
        for sourceURL in sourceURLs {
            let ext = sourceURL.pathExtension
            let nameWithoutExt = (sourceURL.lastPathComponent as NSString).deletingPathExtension
            let isDir = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            var destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)

            // Resolve conflicts
            if fm.fileExists(atPath: destinationURL.path) {
                if isDir && ext.isEmpty {
                    let name = availableFolderName(in: destinationDirectory, baseName: nameWithoutExt)
                    destinationURL = destinationDirectory.appendingPathComponent(name)
                } else {
                    let name = availableFilename(
                        in: destinationDirectory,
                        baseName: nameWithoutExt,
                        extension: ext
                    )
                    destinationURL = destinationDirectory.appendingPathComponent(name)
                }
            }

            try fm.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    // MARK: - Helpers

    /// Sets POSIX permissions to 0o755 (owner rwx, group rx, others rx).
    private func setExecutablePermission(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    /// Returns the first available folder name in the directory, auto-incrementing if needed.
    /// Example: "untitled" → "untitled 2" → "untitled 3"
    private func availableFolderName(in directory: URL, baseName: String) -> String {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))
            .map(Set.init) ?? []
        if !existing.contains(baseName) { return baseName }
        var counter = 2
        while true {
            let candidate = "\(baseName) \(counter)"
            if !existing.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Returns the first available filename in the directory, auto-incrementing if needed.
    /// Example: "untitled.md" → "untitled 2.md" → "untitled 3.md"
    private func availableFilename(
        in directory: URL,
        baseName: String,
        extension ext: String
    ) -> String {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))
            .map(Set.init) ?? []
        let first = "\(baseName).\(ext)"
        if !existing.contains(first) { return first }
        var counter = 2
        while true {
            let candidate = "\(baseName) \(counter).\(ext)"
            if !existing.contains(candidate) { return candidate }
            counter += 1
        }
    }

    // MARK: - Errors

    enum FileOperationError: Error, LocalizedError {
        case createFailed(URL)

        var errorDescription: String? {
            switch self {
            case .createFailed(let url):
                return "Failed to create file at \(url.path)"
            }
        }
    }
}
