// IndexService.swift
// Actor-isolated SQLite/FTS5 search index. Builds and maintains a persistent
// file metadata index for fast filename and content search.
// All database access runs off the main thread via actor isolation.

import Foundation
import os.log
import SQLite3
import UniformTypeIdentifiers

/// Diagnostic logger for the index pipeline (temporary — remove once search is stable).
private let indexLog = Logger(subsystem: "com.velocity.search", category: "IndexService")

/// Named constant for SQLITE_TRANSIENT destructor type.
/// Tells SQLite to make its own copy of bound text/blob data immediately,
/// so the caller's memory can be freed or reused after binding.
private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor IndexService {

    // MARK: - Database Handle

    /// Raw SQLite connection. Opened on first use, closed on deinit.
    /// `nonisolated(unsafe)` allows cleanup in deinit (which is nonisolated in Swift 6).
    private nonisolated(unsafe) var db: OpaquePointer?

    /// Directory path for the SQLite database file.
    private static let indexDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Velocity", isDirectory: true)
            .appendingPathComponent("search-index", isDirectory: true)
    }()

    /// Path to the SQLite database file.
    private static let dbPath: String = {
        indexDirectory.appendingPathComponent("index.db").path
    }()

    /// Maximum file size (in bytes) to attempt content indexing.
    /// Files larger than this are indexed by name/metadata only.
    private static let maxContentSize: Int64 = 1_048_576 // 1 MB

    /// FSEvents stream for watching indexed directories.
    /// `nonisolated(unsafe)` because cleanup in deinit is nonisolated.
    private nonisolated(unsafe) var eventStream: FSEventStreamRef?

    /// The directory currently being watched by FSEvents.
    private var watchedDirectory: URL?

    // MARK: - Init / Deinit

    /// Whether the database has been opened. Checked lazily on first query.
    private var isOpen = false

    /// Ensures the database is open before any operation.
    private func ensureOpen() {
        guard !isOpen else { return }
        isOpen = true
        openDatabase()
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        if let db { sqlite3_close(db) }
    }

    // MARK: - Database Setup

    /// Opens (or creates) the SQLite database and creates tables if needed.
    private func openDatabase() {
        // Ensure the directory exists
        try? FileManager.default.createDirectory(
            at: Self.indexDirectory,
            withIntermediateDirectories: true
        )

        guard sqlite3_open(Self.dbPath, &db) == SQLITE_OK else {
            NSLog("IndexService: Failed to open database at \(Self.dbPath)")
            return
        }

        // WAL mode for concurrent reads during writes
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")

        // Performance tuning: 8MB page cache, 256MB mmap window, temp tables in memory
        exec("PRAGMA cache_size=-8000")
        exec("PRAGMA mmap_size=268435456")
        exec("PRAGMA temp_store=MEMORY")

        // Main files table — stores file metadata
        exec("""
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                parent_path TEXT NOT NULL,
                size INTEGER NOT NULL DEFAULT 0,
                date_modified REAL NOT NULL DEFAULT 0,
                is_directory INTEGER NOT NULL DEFAULT 0,
                content_text TEXT
            )
        """)

        // FTS5 virtual table for full-text search over name and content
        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                name,
                content_text,
                content='files',
                content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            )
        """)

        // Triggers to keep FTS5 index in sync with files table
        exec("""
            CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
                INSERT INTO files_fts(rowid, name, content_text)
                VALUES (new.id, new.name, new.content_text);
            END
        """)

        exec("""
            CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, name, content_text)
                VALUES ('delete', old.id, old.name, old.content_text);
            END
        """)

        exec("""
            CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, name, content_text)
                VALUES ('delete', old.id, old.name, old.content_text);
                INSERT INTO files_fts(rowid, name, content_text)
                VALUES (new.id, new.name, new.content_text);
            END
        """)

        // Index on parent_path for scoped queries
        exec("CREATE INDEX IF NOT EXISTS idx_files_parent ON files(parent_path)")

        // Index on path for fast lookups during incremental updates
        exec("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)")

        // One-time migration: clear stale index data built with FTS_NOSTAT bug
        // (files were never indexed — only directories — so the index is useless).
        // Clearing forces fresh raw search fallback until re-indexing completes.
        migrateIfNeeded()
    }

    /// Schema version key stored in SQLite user_version pragma.
    /// Bump this when a migration requires clearing stale data.
    private static let currentSchemaVersion: Int32 = 2

    /// Runs one-time migrations based on the stored schema version.
    private func migrateIfNeeded() {
        guard let db else { return }

        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }

        if version < Self.currentSchemaVersion {
            // Clear stale data from the FTS_NOSTAT era
            exec("DELETE FROM files")
            exec("INSERT INTO files_fts(files_fts) VALUES('rebuild')")
            exec("PRAGMA user_version = \(Self.currentSchemaVersion)")
        }
    }

    /// Executes a SQL statement with no result. Logs errors.
    private func exec(_ sql: String) {
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            NSLog("IndexService SQL error: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Indexing

    /// Recursively indexes all files under the given directory.
    /// Uses POSIX fts(3) for maximum enumeration speed.
    /// Throttles I/O priority to avoid impacting user experience.
    func indexDirectory(at url: URL) {
        ensureOpen()

        // Set background I/O priority for this operation
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_THROTTLE)
        defer { setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_DEFAULT) }

        guard let db else { return }

        let basePath = url.path

        // Begin transaction for bulk inserts
        exec("BEGIN TRANSACTION")

        // Use fts(3) for recursive enumeration
        let pathCStr = basePath.withCString { strdup($0) }!
        defer { free(pathCStr) }

        var paths: [UnsafeMutablePointer<CChar>?] = [pathCStr, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            exec("ROLLBACK")
            return
        }
        defer { fts_close(fts) }

        var insertStmt: OpaquePointer?
        let insertSQL = """
            INSERT OR REPLACE INTO files (name, path, parent_path, size, date_modified, is_directory, content_text)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            exec("ROLLBACK")
            return
        }
        defer { sqlite3_finalize(insertStmt) }

        var batchCount = 0

        while let entry = fts_read(fts) {
            // Check for task cancellation
            guard !Task.isCancelled else { break }

            let info = entry.pointee.fts_info
            let entryPath = String(cString: entry.pointee.fts_path)
            let entryName = withUnsafePointer(to: &entry.pointee.fts_name) { namePtr in
                namePtr.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.fts_namelen)) { ptr in
                    String(cString: ptr)
                }
            }

            // Skip . and .. entries
            guard entryName != "." && entryName != ".." else { continue }

            // Skip inaccessible entries
            guard info != FTS_ERR && info != FTS_DNR && info != FTS_NS else { continue }

            // Skip hidden directories (but not their contents if already entered)
            if info == FTS_D && entryName.hasPrefix(".") {
                fts_set(fts, entry, FTS_SKIP)
                continue
            }

            // Only process files and directories (not post-order directory visits)
            guard info == FTS_F || info == FTS_D else { continue }

            let isDirectory = info == FTS_D

            // stat the file for metadata
            var statBuf = stat()
            guard lstat(entryPath, &statBuf) == 0 else { continue }

            let size = Int64(statBuf.st_size)
            let mtime = TimeInterval(statBuf.st_mtimespec.tv_sec)

            // Parent path via String slicing — avoids NSString bridging
            let parentPath = entryPath.parentPathFast

            // Check if file is already indexed with same mtime (incremental update)
            if let existingMtime = queryMtime(path: entryPath), existingMtime == mtime {
                continue
            }

            // Extract content for text files (skip binary, skip large files)
            var contentText: String?
            if !isDirectory && size <= Self.maxContentSize && size > 0 {
                contentText = extractTextContent(at: entryPath, name: entryName)
            }

            // Bind parameters and execute insert
            sqlite3_bind_text(insertStmt, 1, entryName, -1, SQLITE_TRANSIENT_PTR)
            sqlite3_bind_text(insertStmt, 2, entryPath, -1, SQLITE_TRANSIENT_PTR)
            sqlite3_bind_text(insertStmt, 3, parentPath, -1, SQLITE_TRANSIENT_PTR)
            sqlite3_bind_int64(insertStmt, 4, sqlite3_int64(size))
            sqlite3_bind_double(insertStmt, 5, mtime)
            sqlite3_bind_int(insertStmt, 6, isDirectory ? 1 : 0)

            if let text = contentText {
                sqlite3_bind_text(insertStmt, 7, text, -1, SQLITE_TRANSIENT_PTR)
            } else {
                sqlite3_bind_null(insertStmt, 7)
            }

            sqlite3_step(insertStmt)
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)

            batchCount += 1

            // Commit every 500 entries to avoid holding the lock too long
            if batchCount >= 500 {
                exec("COMMIT")
                exec("BEGIN TRANSACTION")
                batchCount = 0
            }
        }

        exec("COMMIT")

        // Start watching for changes
        startWatching(url)
    }

    /// Queries the stored mtime for a given path. Returns nil if not indexed.
    private func queryMtime(path: String) -> TimeInterval? {
        guard let db else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT date_modified FROM files WHERE path = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT_PTR)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_double(stmt, 0)
    }

    /// Extracts plain text content from a file if it's a known text type.
    /// Returns nil for binary files or on read failure.
    private func extractTextContent(at path: String, name: String) -> String? {
        // Use shared text detection utility — avoids per-call Set allocation
        guard TextFileDetection.isText(name: name) else { return nil }

        // Read file content with a size cap
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }

    // MARK: - Search Queries

    /// Searches filenames using FTS5. Returns results scoped to the given directory tree.
    func searchFilenames(
        query: String,
        under directory: URL,
        limit: Int = 200
    ) -> [SearchResult] {
        ensureOpen()
        guard let db, !query.isEmpty else { return [] }

        let dirPath = directory.path
        var results: [SearchResult] = []

        // Use LIKE for substring matching so "google" finds "googleSolver.py".
        // FTS5 tokenizes on word boundaries, which misses intra-word matches.
        var stmt: OpaquePointer?
        let sql = """
            SELECT name, path, size, date_modified, is_directory
            FROM files
            WHERE name LIKE ? AND path LIKE ?
            ORDER BY name
            LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        // Escape LIKE wildcards in the user query, then wrap with %
        let escaped = query
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        sqlite3_bind_text(stmt, 1, "%\(escaped)%", -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 2, dirPath + "%", -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let result = buildSearchResult(from: stmt, matchExcerpt: nil, matchLine: nil) {
                results.append(result)
            }
        }

        indexLog.debug("[searchFilenames] query='\(query)' returned \(results.count) results")
        return results
    }

    /// Searches file contents using FTS5. Returns results with matching excerpts.
    func searchContent(
        query: String,
        under directory: URL,
        limit: Int = 200
    ) -> [SearchResult] {
        ensureOpen()
        guard let db, !query.isEmpty else { return [] }

        let dirPath = directory.path
        var results: [SearchResult] = []

        var stmt: OpaquePointer?
        let sql = """
            SELECT f.name, f.path, f.size, f.date_modified, f.is_directory,
                   snippet(files_fts, 1, '>>>', '<<<', '...', 40) AS excerpt
            FROM files f
            JOIN files_fts fts ON f.id = fts.rowid
            WHERE files_fts MATCH ? AND f.path LIKE ? AND f.is_directory = 0
            ORDER BY rank
            LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let ftsQuery = "content_text : \(fts5Escape(query))"
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 2, dirPath + "%", -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let excerpt = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            if let result = buildSearchResult(from: stmt, matchExcerpt: excerpt, matchLine: nil) {
                results.append(result)
            }
        }

        indexLog.debug("[searchContent] query='\(query)' returned \(results.count) results")
        return results
    }

    /// Checks whether the given directory has been indexed.
    /// Uses EXISTS for early exit — avoids counting all matching rows.
    func isDirectoryIndexed(_ url: URL) -> Bool {
        ensureOpen()
        guard let db else { return false }

        var stmt: OpaquePointer?
        let sql = "SELECT EXISTS(SELECT 1 FROM files WHERE path LIKE ? LIMIT 1)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let pattern = url.path + "%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT_PTR)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int(stmt, 0) != 0
    }

    // MARK: - Helpers

    /// Builds a SearchResult from a SQLite result row.
    /// Columns: 0=name, 1=path, 2=size, 3=date_modified, 4=is_directory
    private func buildSearchResult(
        from stmt: OpaquePointer?,
        matchExcerpt: String?,
        matchLine: Int?
    ) -> SearchResult? {
        guard let stmt,
              let namePtr = sqlite3_column_text(stmt, 0),
              let pathPtr = sqlite3_column_text(stmt, 1) else { return nil }

        let name = String(cString: namePtr)
        let path = String(cString: pathPtr)
        let size = sqlite3_column_int64(stmt, 2)
        let mtime = sqlite3_column_double(stmt, 3)
        let isDir = sqlite3_column_int(stmt, 4) != 0

        let ext = name.pathExtensionFast
        let fileType: UTType? = isDir ? .folder : UTType(filenameExtension: ext)

        let fileItem = FileItem(
            name: name,
            path: path,
            size: size,
            dateModified: Date(timeIntervalSince1970: mtime),
            isDirectory: isDir,
            isHidden: name.hasPrefix("."),
            fileType: fileType
        )

        return SearchResult(
            fileItem: fileItem,
            matchExcerpt: matchExcerpt,
            matchLine: matchLine
        )
    }

    /// Escapes a query string for safe use in FTS5 MATCH expressions.
    /// Wraps each word in double quotes to treat as literal tokens.
    private func fts5Escape(_ query: String) -> String {
        let words = query.split(separator: " ", omittingEmptySubsequences: true)
        return words.map { "\"\($0)\"" }.joined(separator: " ")
    }

    // MARK: - FSEvents Watching

    /// Starts watching a directory for filesystem changes. Triggers incremental re-index.
    private func startWatching(_ directory: URL) {
        if watchedDirectory == directory, eventStream != nil { return }
        stopWatching()
        watchedDirectory = directory

        let path = directory.path as CFString
        var context = FSEventStreamContext()
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        context.info = pointer

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let service = Unmanaged<IndexService>.fromOpaque(info).takeUnretainedValue()
                Task {
                    await service.handleFSEvent()
                }
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0, // 2 second latency — coalesce rapid changes
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        eventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    /// Stops the current FSEvents watcher.
    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        watchedDirectory = nil
    }

    /// Handles an FSEvents notification by re-indexing the watched directory.
    private func handleFSEvent() {
        guard let dir = watchedDirectory else { return }
        indexDirectory(at: dir)
    }
}
