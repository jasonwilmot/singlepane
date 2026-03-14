// FilePanelViewModel.swift
// Observable view model for a single file explorer pane.
// Drives the NSTableView via @Observable property changes.
// All UI-facing work is @MainActor; file enumeration is delegated to FileService actor.

import Foundation
import Observation
import os.log

/// Diagnostic logger for the search pipeline (temporary — remove once search is stable).
private let searchLog = Logger(subsystem: "com.velocity.search", category: "ViewModel")

@Observable
@MainActor
final class FilePanelViewModel {

    // MARK: - Published State

    var currentDirectory: URL
    var items: [FileItem] = []
    var isLoading: Bool = false

    /// Currently selected file URL (for preview integration).
    var selectedFileURL: URL?

    // MARK: - View Mode State

    /// Active view mode for this tab. Persisted per-tab via ViewModeStore.
    var viewMode: ViewMode = .list

    /// Unique identifier for this tab, used to persist view mode.
    let tabID: String

    // MARK: - Filter State (FAYT)

    /// Active filter text applied to the file list. Empty string means no filter.
    var filterText: String = ""

    /// Full unfiltered directory listing. `items` is derived from this via `applyFilter()`.
    private var allItems: [FileItem] = []

    // MARK: - Search State

    /// Whether the file panel is in deep search mode (recursive search, not FAYT filter).
    var isSearchMode: Bool = false

    /// Whether a search is actively running (stream in progress).
    /// Drives the spinner in the breadcrumb bar.
    var isSearching: Bool = false

    /// Whether at least one search has completed in the current search session.
    /// Used to suppress "No results" until we've actually searched.
    var hasSearchCompleted: Bool = false

    /// Current search query text.
    var searchQuery: String = ""

    /// Search results streamed from SearchService.
    var searchResults: [SearchResult] = []

    /// Active search mode (filename vs content).
    var activeSearchMode: SearchMode = .filename

    /// Active search options (case sensitive, regex).
    var activeSearchOptions = SearchOptions()

    /// Stashed directory listing for restoration when exiting search mode.
    private var stashedItems: [FileItem] = []

    /// Stashed current directory for restoration when exiting search mode.
    private var stashedDirectory: URL?

    /// In-flight search task — cancelled when query changes or search exits.
    private var searchTask: Task<Void, Never>?

    /// Debounce timer for search input.
    private var searchDebounceTimer: Timer?

    /// Shared SearchService instance for this panel.
    private let searchService = SearchService()

    // MARK: - Ghost Breadcrumb State

    /// Trailing path component names shown as ghost (faded) breadcrumbs.
    /// Example: navigating up from /Users/jason/Projects/app/src to /Users/jason
    /// yields ghostPathComponents = ["Projects", "app", "src"] (capped at 4).
    var ghostPathComponents: [String] = []

    /// The directory from which the ghost trail extends.
    /// Used to reconstruct full URLs when a ghost crumb is clicked.
    var ghostBasePath: URL?

    /// Maximum number of ghost segments to display.
    static let maxGhostSegments = 4

    // MARK: - Dependencies

    let fileService: FileService

    // MARK: - FSEvents Directory Monitoring

    /// FSEvents stream that watches the current directory for external changes.
    /// `nonisolated(unsafe)` allows access from `deinit` (which is nonisolated in Swift 6).
    /// Safe because all live access is on @MainActor; deinit is the sole owner.
    private nonisolated(unsafe) var eventStream: FSEventStreamRef?

    /// The directory currently being watched, to avoid restarting the watcher unnecessarily.
    private var watchedDirectory: URL?

    // MARK: - Init

    init(initialDirectory: URL, fileService: FileService = FileService(), tabID: String = UUID().uuidString) {
        self.currentDirectory = initialDirectory
        self.fileService = fileService
        self.tabID = tabID
        self.viewMode = ViewModeStore.loadViewMode(forTab: tabID)
    }

    /// Cycles to the next implemented view mode and persists the change.
    func cycleViewMode() {
        viewMode = viewMode.next
        ViewModeStore.save(viewMode: viewMode, forTab: tabID)
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Navigation

    /// Navigate into a directory and reload contents.
    /// Updates ghost breadcrumb state based on the navigation relationship.
    /// Clears any active FAYT filter — new directory is a fresh context.
    func navigateTo(_ url: URL) {
        let oldDirectory = currentDirectory
        updateGhostState(navigatingFrom: oldDirectory, to: url)
        clearFilter()
        if isSearchMode { exitSearchMode() }
        currentDirectory = url
        Task { await loadDirectory() }
    }

    /// Navigate to the parent directory. Stops at filesystem root.
    func navigateUp() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent != currentDirectory else { return }
        navigateTo(parent)
    }

    // MARK: - Ghost State Logic

    /// Computes the new ghost breadcrumb state when navigating between directories.
    private func updateGhostState(navigatingFrom oldURL: URL, to newURL: URL) {
        let oldComponents = oldURL.standardizedFileURL.pathComponents
        let newComponents = newURL.standardizedFileURL.pathComponents

        // Case 1: Navigating UP — new path is a prefix of (old path + ghost trail)
        // Combine current path with existing ghosts to get the full remembered trail
        let fullTrailComponents: [String]
        if let ghostBase = ghostBasePath {
            let ghostBaseComponents = ghostBase.standardizedFileURL.pathComponents
            if ghostBaseComponents == oldComponents {
                // Ghost trail extends from current directory
                fullTrailComponents = oldComponents + ghostPathComponents
            } else {
                fullTrailComponents = oldComponents
            }
        } else {
            fullTrailComponents = oldComponents
        }

        if newComponents.count < fullTrailComponents.count,
           Array(fullTrailComponents.prefix(newComponents.count)) == newComponents {
            // New path is an ancestor — preserve the deeper segments as ghosts
            let trailingSegments = Array(fullTrailComponents.suffix(from: newComponents.count))
            ghostPathComponents = Array(trailingSegments.suffix(Self.maxGhostSegments))
            ghostBasePath = newURL
            return
        }

        // Case 2: Navigating INTO a ghost crumb — trim the ghost trail.
        // Only triggers if the new URL actually lies along the ghost path,
        // not just any child of the ghost base (e.g., a sibling directory).
        if let ghostBase = ghostBasePath, !ghostPathComponents.isEmpty {
            let baseComponents = ghostBase.standardizedFileURL.pathComponents
            let depth = newComponents.count - baseComponents.count
            if depth > 0, depth <= ghostPathComponents.count,
               newComponents.starts(with: baseComponents) {
                // Verify each new segment matches the ghost trail in order
                let newSegments = Array(newComponents.suffix(depth))
                let expectedSegments = Array(ghostPathComponents.prefix(depth))
                if newSegments == expectedSegments {
                    let remaining = Array(ghostPathComponents.suffix(from: depth))
                    ghostPathComponents = remaining
                    ghostBasePath = newURL
                    if ghostPathComponents.isEmpty {
                        ghostBasePath = nil
                    }
                    return
                }
            }
        }

        // Case 3: Navigating to a sibling or unrelated path — clear ghosts
        ghostPathComponents = []
        ghostBasePath = nil
    }

    /// Returns true if `child` is a descendant of `ancestor`.
    private func isDescendant(_ child: URL, of ancestor: URL) -> Bool {
        let childComponents = child.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        guard childComponents.count > ancestorComponents.count else { return false }
        return Array(childComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    /// Resolves the full URL for a ghost breadcrumb at the given index.
    /// Index 0 is the first ghost segment after the current directory.
    func resolveGhostCrumb(at index: Int) -> URL? {
        guard let base = ghostBasePath,
              index >= 0, index < ghostPathComponents.count else { return nil }
        var url = base
        for i in 0...index {
            url = url.appendingPathComponent(ghostPathComponents[i])
        }
        return url
    }

    /// Reload the current directory.
    func refresh() {
        Task { await loadDirectory() }
    }

    // MARK: - File Creation

    /// URL of a newly created file, set after creation so the VC can select + rename it.
    var pendingNewFileURL: URL?

    /// Creates a new folder in the current directory.
    /// After creation, reloads the directory and sets `pendingNewFileURL`
    /// so the view controller can select the new row and begin inline rename.
    func createNewFolder() async {
        do {
            let folderURL = try await fileService.createFolder(in: currentDirectory)
            await loadDirectory()
            pendingNewFileURL = folderURL
        } catch {
            NSLog("Folder creation failed: \(error.localizedDescription)")
        }
    }

    /// Creates a new file from a template in the current directory.
    /// After creation, reloads the directory and sets `pendingNewFileURL`
    /// so the view controller can select the new row and begin inline rename.
    func createNewFile(template: FileTemplate) async {
        do {
            let fileURL = try await fileService.createFile(
                in: currentDirectory,
                template: template
            )
            await loadDirectory()
            pendingNewFileURL = fileURL
        } catch {
            NSLog("File creation failed: \(error.localizedDescription)")
        }
    }

    /// Renames a file and reloads the directory.
    func renameFile(from sourceURL: URL, to newName: String) async {
        do {
            let newURL = try await fileService.renameFile(from: sourceURL, to: newName)
            await loadDirectory()
            NotificationCenter.default.post(
                name: .fileDidRename,
                object: nil,
                userInfo: ["oldURL": sourceURL, "newURL": newURL]
            )
        } catch {
            NSLog("File rename failed: \(error.localizedDescription)")
        }
    }

    /// Moves a file to the Trash and reloads the directory.
    func trashFile(_ url: URL) async {
        do {
            try await fileService.trashFile(at: url)
            await loadDirectory()
        } catch {
            NSLog("File trash failed: \(error.localizedDescription)")
        }
    }

    /// Duplicates a file in the same directory and reloads the directory.
    func duplicateFile(_ url: URL) async {
        do {
            try await fileService.duplicateFile(at: url)
            await loadDirectory()
        } catch {
            NSLog("File duplicate failed: \(error.localizedDescription)")
        }
    }

    /// Pastes files from the given URLs into the current directory and reloads.
    func pasteFiles(_ urls: [URL]) async {
        do {
            try await fileService.pasteFiles(urls, into: currentDirectory)
            await loadDirectory()
        } catch {
            NSLog("File paste failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Loading

    /// Fetches directory contents off the main thread, sorts, and updates items.
    /// Re-applies any active filter after loading.
    /// Starts FSEvents monitoring on the loaded directory.
    func loadDirectory() async {
        isLoading = true
        do {
            let rawItems = try await fileService.listDirectory(at: currentDirectory)
            allItems = Self.sorted(rawItems, by: sortKey, ascending: sortAscending)
            applyFilter()
        } catch {
            allItems = []
            items = []
        }
        isLoading = false
        startWatching(currentDirectory)
    }

    // MARK: - FSEvents Directory Watching

    /// Starts an FSEvents stream on the given directory.
    /// Skips if already watching the same directory. Stops any previous watcher otherwise.
    private func startWatching(_ directory: URL) {
        if watchedDirectory == directory, eventStream != nil { return }
        stopWatching()
        watchedDirectory = directory

        let path = directory.path as CFString
        var context = FSEventStreamContext()

        // Store a raw pointer to self for the C callback
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        context.info = pointer

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let viewModel = Unmanaged<FilePanelViewModel>.fromOpaque(info)
                    .takeUnretainedValue()
                Task { @MainActor in
                    await viewModel.loadDirectory()
                }
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // 300ms latency — coalesce rapid changes
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        eventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    /// Stops the current FSEvents stream, if any.
    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        watchedDirectory = nil
    }

    // MARK: - Search Mode

    /// Enters deep search mode — stashes current directory listing for later restoration.
    func enterSearchMode() {
        guard !isSearchMode else { return }
        isSearchMode = true
        hasSearchCompleted = false
        stashedItems = allItems
        stashedDirectory = currentDirectory
        searchResults = []
        searchQuery = ""
    }

    /// Exits deep search mode — restores the previous directory listing.
    func exitSearchMode() {
        guard isSearchMode else { return }

        // Cancel any in-flight search
        searchTask?.cancel()
        searchTask = nil
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = nil

        isSearchMode = false
        isSearching = false
        searchResults = []
        searchQuery = ""

        // Restore stashed directory state
        if let stashed = stashedDirectory {
            currentDirectory = stashed
        }
        allItems = stashedItems
        items = stashedItems
        stashedItems = []
        stashedDirectory = nil

        applyFilter()
    }

    /// Performs a search with debounce. Called when query text or options change.
    func performSearch(query: String, mode: SearchMode, options: SearchOptions) {
        searchQuery = query
        activeSearchMode = mode
        activeSearchOptions = options

        // Cancel previous debounce
        searchDebounceTimer?.invalidate()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchTask?.cancel()
            searchResults = []
            isSearching = false
            return
        }

        // Debounce 150ms before executing search
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.executeSearch()
            }
        }
    }

    /// Executes the search against SearchService, consuming the result stream.
    private func executeSearch() {
        // Cancel previous search
        searchTask?.cancel()

        let query = searchQuery
        let mode = activeSearchMode
        let options = activeSearchOptions
        let directory = stashedDirectory ?? currentDirectory

        isSearching = true
        searchLog.debug("[executeSearch] starting query='\(query)' mode=\(String(describing: mode)) dir=\(directory.path)")

        // Clear results synchronously before the task starts so the
        // observation fires and re-registers before any batches arrive.
        searchResults = []

        searchTask = Task {
            let stream = await searchService.search(
                query: query,
                in: directory,
                mode: mode,
                options: options
            )

            var accumulated: [SearchResult] = []
            for await batch in stream {
                guard !Task.isCancelled else { break }
                accumulated.append(contentsOf: batch)
                searchLog.debug("[executeSearch] received batch of \(batch.count), total=\(accumulated.count)")
                // Assign the full array each time so observation always fires
                // with the complete result set, avoiding race with re-registration.
                searchResults = accumulated
            }

            searchLog.debug("[executeSearch] stream complete — total results=\(accumulated.count)")
            isSearching = false
            hasSearchCompleted = true
        }
    }

    // MARK: - FAYT Filtering

    /// Filters `allItems` into `items` based on `filterText`.
    /// If `filterText` is empty, shows all items.
    /// Supports `*` as a glob wildcard; otherwise case-insensitive substring match.
    func applyFilter() {
        guard !filterText.isEmpty else {
            items = allItems
            return
        }

        let query = filterText.lowercased()

        if query.contains("*") {
            // Glob-style matching: convert `*` to regex `.*`
            let escaped = NSRegularExpression.escapedPattern(for: query)
                .replacingOccurrences(of: "\\*", with: ".*")
            let pattern = "^\(escaped)$"
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

            items = allItems.filter { item in
                let name = item.name
                guard let regex else { return false }
                let range = NSRange(name.startIndex..., in: name)
                return regex.firstMatch(in: name, range: range) != nil
            }
        } else {
            // Plain case-insensitive substring match
            items = allItems.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Clears the active filter and restores the full file list.
    func clearFilter() {
        filterText = ""
        items = allItems
    }

    // MARK: - Sorting

    /// Current sort key and direction, persisted across directory loads.
    private var sortKey: String = "name"
    private var sortAscending: Bool = true

    /// Sorts items by the given key. Directories always sort first.
    func sort(by key: String, ascending: Bool) {
        sortKey = key
        sortAscending = ascending
        allItems = Self.sorted(allItems, by: key, ascending: ascending)
        applyFilter()
    }

    /// Directories first, then sorted by the given key and direction.
    private static func sorted(_ items: [FileItem], by key: String = "name", ascending: Bool = true) -> [FileItem] {
        items.sorted { lhs, rhs in
            // Directories always first
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let result: ComparisonResult
            switch key {
            case "name":
                result = lhs.name.localizedStandardCompare(rhs.name)
            case "size":
                if lhs.size == rhs.size { result = .orderedSame }
                else { result = lhs.size < rhs.size ? .orderedAscending : .orderedDescending }
            case "date":
                result = lhs.dateModified.compare(rhs.dateModified)
            case "kind":
                let lhsKind = lhs.fileType?.localizedDescription ?? ""
                let rhsKind = rhs.fileType?.localizedDescription ?? ""
                result = lhsKind.localizedStandardCompare(rhsKind)
            default:
                result = lhs.name.localizedStandardCompare(rhs.name)
            }

            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}
