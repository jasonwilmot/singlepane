// SearchService.swift
// Actor-isolated search coordinator. Routes queries to IndexService (FTS5)
// or raw filesystem enumeration (fallback). Streams batched results via AsyncStream.
// Handles cancellation, debounce, and mode/option toggling.

import Foundation
import os.log
import UniformTypeIdentifiers

/// Diagnostic logger for the search pipeline (temporary — remove once search is stable).
private let searchLog = Logger(subsystem: "com.velocity.search", category: "SearchService")

actor SearchService {

    // MARK: - Dependencies

    private let indexService = IndexService()

    // MARK: - Search

    /// Performs a search and streams batches of results as they are found.
    /// Automatically selects indexed (FTS5) or raw (filesystem walk) strategy.
    ///
    /// - Parameters:
    ///   - query: The search text entered by the user.
    ///   - directory: Root directory to scope the search.
    ///   - mode: `.filename` or `.content` search.
    ///   - options: Case sensitivity and regex toggles.
    /// - Returns: An AsyncStream that yields batches of SearchResult arrays.
    func search(
        query: String,
        in directory: URL,
        mode: SearchMode,
        options: SearchOptions
    ) -> AsyncStream<[SearchResult]> {
        AsyncStream { continuation in
            let task = Task {
                defer {
                    searchLog.debug("[search] stream finished for query='\(query)'")
                    continuation.finish()
                }

                // Guard against empty queries
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    searchLog.debug("[search] empty query — skipping")
                    return
                }

                searchLog.debug("[search] query='\(query)' mode=\(String(describing: mode)) dir=\(directory.path)")

                // Regex or case-sensitive searches bypass FTS5 — use raw enumeration
                if options.regex || options.caseSensitive {
                    searchLog.debug("[search] using raw search (regex=\(options.regex) caseSensitive=\(options.caseSensitive))")
                    await rawSearch(
                        query: query,
                        in: directory,
                        mode: mode,
                        options: options,
                        continuation: continuation
                    )
                    return
                }

                // Check if directory is indexed
                let isIndexed = await indexService.isDirectoryIndexed(directory)
                searchLog.debug("[search] isDirectoryIndexed=\(isIndexed)")

                if isIndexed {
                    // Use FTS5 indexed search
                    let results: [SearchResult]
                    switch mode {
                    case .filename:
                        results = await indexService.searchFilenames(query: query, under: directory)
                    case .content:
                        results = await indexService.searchContent(query: query, under: directory)
                    }

                    searchLog.debug("[search] indexed search returned \(results.count) results")
                    if !results.isEmpty {
                        continuation.yield(results)
                    }
                } else {
                    // Trigger background indexing for next time
                    searchLog.debug("[search] triggering background index for \(directory.path)")
                    Task {
                        await indexService.indexDirectory(at: directory)
                    }

                    // Fall back to raw filesystem search
                    searchLog.debug("[search] falling back to raw filesystem search")
                    await rawSearch(
                        query: query,
                        in: directory,
                        mode: mode,
                        options: options,
                        continuation: continuation
                    )
                }
            }

            // Cancel the internal search task when the consumer stops iterating.
            // Without this, rawSearch keeps running on the actor after the consumer
            // cancels, blocking all subsequent searches until traversal completes.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Raw Filesystem Search

    /// Performs a recursive filesystem walk using POSIX fts(3), matching files
    /// against the query. Used as fallback when the directory is not yet indexed,
    /// or when regex/case-sensitive options are active.
    private func rawSearch(
        query: String,
        in directory: URL,
        mode: SearchMode,
        options: SearchOptions,
        continuation: AsyncStream<[SearchResult]>.Continuation
    ) async {
        let basePath = directory.path
        let pathCStr = basePath.withCString { strdup($0) }!
        defer { free(pathCStr) }

        var paths: [UnsafeMutablePointer<CChar>?] = [pathCStr, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return
        }
        defer { fts_close(fts) }

        // Compile regex if needed
        let regex: NSRegularExpression?
        if options.regex {
            let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : .caseInsensitive
            regex = try? NSRegularExpression(pattern: query, options: regexOptions)
        } else {
            regex = nil
        }

        var batch: [SearchResult] = []

        // Adaptive batching: small first batch for fast first paint, then ramp up
        let firstBatchSize = 5
        let steadyBatchSize = 50
        var currentBatchSize = firstBatchSize

        var entriesVisited = 0
        var batchesYielded = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        while let entry = fts_read(fts) {
            guard !Task.isCancelled else { break }

            let info = entry.pointee.fts_info
            let entryName = withUnsafePointer(to: &entry.pointee.fts_name) { namePtr in
                namePtr.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.fts_namelen)) { ptr in
                    String(cString: ptr)
                }
            }

            // Skip . and ..
            guard entryName != "." && entryName != ".." else { continue }

            // Skip inaccessible entries
            guard info != FTS_ERR && info != FTS_DNR && info != FTS_NS else { continue }

            // Skip hidden directories entirely
            if info == FTS_D && entryName.hasPrefix(".") {
                fts_set(fts, entry, FTS_SKIP)
                continue
            }

            // Only process regular files (and directories for filename mode)
            let isFile = info == FTS_F
            let isDir = info == FTS_D

            guard isFile || (isDir && mode == .filename) else { continue }

            entriesVisited += 1
            let entryPath = String(cString: entry.pointee.fts_path)

            switch mode {
            case .filename:
                if matchesQuery(entryName, query: query, regex: regex, options: options) {
                    if let result = buildRawResult(name: entryName, path: entryPath, isDirectory: isDir) {
                        batch.append(result)
                    }
                }

            case .content:
                guard isFile else { continue }
                if let match = searchFileContent(
                    at: entryPath,
                    name: entryName,
                    query: query,
                    regex: regex,
                    options: options
                ) {
                    batch.append(match)
                }
            }

            // Yield batch when full — ramp from small to large after first yield
            if batch.count >= currentBatchSize {
                batchesYielded += 1
                searchLog.debug("[rawSearch] yielding batch #\(batchesYielded) (\(batch.count) results)")
                continuation.yield(batch)
                batch = []
                currentBatchSize = steadyBatchSize
            }
        }

        // Yield remaining results
        if !batch.isEmpty {
            batchesYielded += 1
            searchLog.debug("[rawSearch] yielding final batch #\(batchesYielded) (\(batch.count) results)")
            continuation.yield(batch)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        searchLog.debug("[rawSearch] done — visited=\(entriesVisited) batches=\(batchesYielded) elapsed=\(String(format: "%.3f", elapsed))s")
    }

    /// Checks whether a string matches the query using the configured match strategy.
    private func matchesQuery(
        _ text: String,
        query: String,
        regex: NSRegularExpression?,
        options: SearchOptions
    ) -> Bool {
        if let regex {
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }

        if options.caseSensitive {
            return text.contains(query)
        }

        // Non-locale case-insensitive search — avoids per-call allocations
        // from localizedCaseInsensitiveContains while being faster for filenames.
        return text.range(of: query, options: .caseInsensitive) != nil
    }

    // MARK: - Content Search (mmap)

    /// Searches a file's content for the query using memory-mapped I/O.
    /// Maps the file into virtual memory and scans bytes line-by-line,
    /// only converting the matching line region to a String.
    /// Falls back to FileManager read if mmap fails.
    private func searchFileContent(
        at path: String,
        name: String,
        query: String,
        regex: NSRegularExpression?,
        options: SearchOptions
    ) -> SearchResult? {
        // Check file size — skip large files and empty files
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0,
              statBuf.st_size <= 1_048_576,
              statBuf.st_size > 0 else { return nil }

        // Check if this is a text file via shared detection utility
        guard TextFileDetection.isText(name: name) else { return nil }

        let fileSize = Int(statBuf.st_size)

        // Try mmap-based search first (2-5x faster than FileManager read)
        if let result = mmapSearchContent(
            at: path, name: name, fileSize: fileSize,
            query: query, regex: regex, options: options
        ) {
            return result
        }

        // Fallback: FileManager read for special filesystems where mmap fails
        return fallbackSearchContent(
            at: path, name: name,
            query: query, regex: regex, options: options
        )
    }

    /// Memory-mapped content search. Opens the file, maps it into virtual memory,
    /// and scans for matching lines without copying the entire file into a String.
    private func mmapSearchContent(
        at path: String,
        name: String,
        fileSize: Int,
        query: String,
        regex: NSRegularExpression?,
        options: SearchOptions
    ) -> SearchResult? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        guard let mapped = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, fd, 0),
              mapped != MAP_FAILED else { return nil }
        defer { munmap(mapped, fileSize) }

        // Hint to the kernel that we'll read sequentially
        madvise(mapped, fileSize, MADV_SEQUENTIAL)

        let bytes = mapped.assumingMemoryBound(to: UInt8.self)
        var lineStart = 0
        var lineNumber = 0

        while lineStart < fileSize {
            lineNumber += 1

            // Find end of current line
            var lineEnd = lineStart
            while lineEnd < fileSize && bytes[lineEnd] != 0x0A { // newline
                lineEnd += 1
            }

            // Strip trailing CR for CRLF files
            var lineContentEnd = lineEnd
            if lineContentEnd > lineStart && bytes[lineContentEnd - 1] == 0x0D {
                lineContentEnd -= 1
            }

            let lineLength = lineContentEnd - lineStart
            if lineLength > 0 {
                // Convert only this line's bytes to a String for matching
                let lineData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes + lineStart),
                                    count: lineLength, deallocator: .none)
                if let line = String(data: lineData, encoding: .utf8) {
                    if matchesQuery(line, query: query, regex: regex, options: options) {
                        let excerpt = String(line.trimmingCharacters(in: .whitespaces).prefix(200))
                        return buildRawResult(
                            name: name, path: path, isDirectory: false,
                            excerpt: excerpt, line: lineNumber
                        )
                    }
                }
            }

            // Advance past the newline
            lineStart = lineEnd + 1
        }

        return nil
    }

    /// Fallback content search using FileManager for when mmap is unavailable.
    private func fallbackSearchContent(
        at path: String,
        name: String,
        query: String,
        regex: NSRegularExpression?,
        options: SearchOptions
    ) -> SearchResult? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var lineNumber = 0
        for line in content.components(separatedBy: .newlines) {
            lineNumber += 1
            if matchesQuery(line, query: query, regex: regex, options: options) {
                let excerpt = String(line.trimmingCharacters(in: .whitespaces).prefix(200))
                return buildRawResult(
                    name: name, path: path, isDirectory: false,
                    excerpt: excerpt, line: lineNumber
                )
            }
        }

        return nil
    }

    // MARK: - Result Building

    /// Builds a SearchResult from raw filesystem data.
    /// Defers URL creation by storing the path string directly in FileItem.
    private func buildRawResult(
        name: String,
        path: String,
        isDirectory: Bool,
        excerpt: String? = nil,
        line: Int? = nil
    ) -> SearchResult? {
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else { return nil }

        let ext = name.pathExtensionFast
        let fileType: UTType? = isDirectory ? .folder : UTType(filenameExtension: ext)

        let fileItem = FileItem(
            name: name,
            path: path,
            size: Int64(statBuf.st_size),
            dateModified: Date(timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec)),
            isDirectory: isDirectory,
            isHidden: name.hasPrefix("."),
            fileType: fileType
        )

        return SearchResult(
            fileItem: fileItem,
            matchExcerpt: excerpt,
            matchLine: line
        )
    }
}
