// DirectoryEnumerator.swift
// POSIX-based directory enumeration using opendir/readdir + lstat.
// Bypasses Foundation overhead for maximum performance on large directories.

import Foundation
import UniformTypeIdentifiers

enum DirectoryEnumerator: Sendable {

    enum EnumerationError: Error {
        case cannotOpenDirectory(URL)
    }

    /// Enumerate all entries in a directory using POSIX APIs.
    /// Returns unsorted array of FileItem. Skips "." and "..".
    static func enumerate(at url: URL) throws -> [FileItem] {
        let path = url.path
        guard let dir = opendir(path) else {
            throw EnumerationError.cannotOpenDirectory(url)
        }
        defer { closedir(dir) }

        var items: [FileItem] = []

        while let entry = readdir(dir) {
            let name = extractName(from: entry)

            // Skip current/parent directory entries and preview temp files
            if name == "." || name == ".." { continue }
            if name.hasPrefix(".singlepane-preview") && name.hasSuffix(".html") { continue }

            let fullPath = path + "/" + name

            // stat the file to get metadata
            var statBuf = stat()
            guard lstat(fullPath, &statBuf) == 0 else { continue }

            let isDirectory = (statBuf.st_mode & S_IFMT) == S_IFDIR
            let isHidden = name.hasPrefix(".")
            let size = Int64(statBuf.st_size)
            let dateModified = Date(
                timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec)
            )

            // Determine file type from extension
            let ext = name.pathExtensionFast
            let fileType: UTType? = if isDirectory {
                .folder
            } else {
                UTType(filenameExtension: ext)
            }

            items.append(FileItem(
                name: name,
                path: fullPath,
                size: size,
                dateModified: dateModified,
                isDirectory: isDirectory,
                isHidden: isHidden,
                fileType: fileType
            ))
        }

        return items
    }

    /// Extract the filename from a dirent entry's d_name tuple.
    private static func extractName(from entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: &entry.pointee.d_name) { namePtr in
            namePtr.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen)) { ptr in
                String(cString: ptr)
            }
        }
    }
}
