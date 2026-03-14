// TerminalLinkDetector.swift
// Detects clickable URLs and file paths in terminal output text.
// Used by the terminal's click-to-open and hover handlers to identify
// links at a specific column position within a line of terminal output.

import Foundation

// MARK: - Detected Link

/// A link found in terminal output text.
enum DetectedLink {
    /// A web URL (http:// or https://).
    case url(String, range: Range<String.Index>)
    /// A local file path with optional line and column numbers.
    case filePath(path: String, line: Int?, col: Int?, range: Range<String.Index>)
    /// A git commit hash (7–12 hex characters).
    case gitHash(String, range: Range<String.Index>)
}

// MARK: - Link Detector

/// Scans a line of terminal text for URLs and file paths at a given cursor position.
/// Supports:
///   - HTTP/HTTPS URLs
///   - Absolute paths (`/Users/...`)
///   - Explicit relative paths (`./src/...`, `../lib/...`)
///   - Tilde paths (`~/Documents/...`)
///   - Bare relative paths (`research/capabilities.md`, `src/main.swift`)
///   - Bare filenames (`nuxt.config.ts`, `README.md`, `package.json`)
///   - Line:col suffixes (`file.swift:42:10`)
///   - File existence validation for paths
@MainActor
enum TerminalLinkDetector {

    // MARK: - Regex Patterns

    /// Matches http:// and https:// URLs.
    /// Stops at whitespace, closing parens/brackets not part of the URL, and common punctuation.
    private static let urlPattern: String =
        #"https?://[^\s<>\"\'\]\)}`]+"#

    /// Matches file paths in terminal output. Handles:
    ///   - Absolute:       /Users/foo/bar.txt
    ///   - Tilde:          ~/Documents/file.md
    ///   - Explicit relative: ./src/main.swift, ../lib/util.swift
    ///   - Bare relative:  research/capabilities.md, src/main.swift
    /// Captures optional :line and :line:col suffixes.
    /// Paths must end with a word character or `/` (for directories like `.claude/commands/`).
    /// Spaces are excluded to prevent over-matching into surrounding text.
    /// Bare relative paths are validated against the filesystem.
    private static let filePathPattern: String =
        #"(?:[~.]?/|[\w\-.][\w\-.]*/)[\w\-./\\]+[\w/](?::(\d+))?(?::(\d+))?"#

    /// Compiled regex for URL detection.
    private static let urlRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: urlPattern, options: [])
    }()

    /// Compiled regex for file path detection.
    private static let filePathRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: filePathPattern, options: [])
    }()

    /// Matches bare filenames without any directory path component.
    /// E.g., `nuxt.config.ts`, `README.md`, `package.json`, `file.swift:42:10`.
    /// Requires at least one dot with a letter-starting extension to avoid matching
    /// version numbers (`v2.0`) or numeric tokens. Validated against the filesystem
    /// (resolved relative to CWD) so false positives are filtered automatically.
    private static let bareFilenamePattern: String =
        #"\b[\w][\w\-.]*\.[a-zA-Z][\w]*(?::(\d+))?(?::(\d+))?"#

    /// Compiled regex for bare filename detection.
    private static let bareFilenameRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: bareFilenamePattern, options: [])
    }()

    // MARK: - Detection

    /// Finds the link (URL or file path) at the given column position in a line of text.
    /// - Parameters:
    ///   - line: A single line of terminal output text.
    ///   - column: The zero-based column (character offset) where the cursor is.
    ///   - cwd: Current working directory for resolving relative paths. Nil disables relative path matching.
    /// - Returns: The detected link if one exists at the cursor position, nil otherwise.
    static func detect(in line: String, at column: Int, cwd: String?) -> DetectedLink? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // Check URLs first — they take priority over file paths
        if let match = findMatch(regex: urlRegex, in: line, nsRange: fullRange, at: column) {
            let urlString = nsLine.substring(with: match.range)
            let range = Range(match.range, in: line)!
            return .url(urlString, range: range)
        }

        // Check file paths (with directory components)
        if let match = findMatch(regex: filePathRegex, in: line, nsRange: fullRange, at: column) {
            return parseFilePathMatch(match, in: line, nsLine: nsLine, cwd: cwd)
        }

        // Check bare filenames (no directory path, e.g. nuxt.config.ts)
        if let match = findMatch(regex: bareFilenameRegex, in: line, nsRange: fullRange, at: column) {
            return parseFilePathMatch(match, in: line, nsLine: nsLine, cwd: cwd)
        }

        return nil
    }

    // MARK: - Bulk Detection

    /// Finds all links (URLs and file paths) on a line of terminal text.
    /// Used for persistent underlines — scans the entire line rather than a single column.
    /// URLs take priority: file path matches that overlap a URL match are skipped.
    static func detectAll(in line: String, cwd: String?) -> [DetectedLink] {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        var results: [DetectedLink] = []

        // Collect all URL matches
        if let regex = urlRegex {
            for match in regex.matches(in: line, options: [], range: fullRange) {
                let urlString = nsLine.substring(with: match.range)
                if let range = Range(match.range, in: line) {
                    results.append(.url(urlString, range: range))
                }
            }
        }

        // Collect file path matches, skipping any that overlap with URL matches
        if let regex = filePathRegex {
            let urlRanges = results.map { link -> NSRange in
                switch link {
                case .url(_, let r): return NSRange(r, in: line)
                case .filePath(_, _, _, let r): return NSRange(r, in: line)
                case .gitHash(_, let r): return NSRange(r, in: line)
                }
            }

            for match in regex.matches(in: line, options: [], range: fullRange) {
                let overlaps = urlRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
                if overlaps { continue }

                if let link = parseFilePathMatch(match, in: line, nsLine: nsLine, cwd: cwd) {
                    results.append(link)
                }
            }
        }

        // Collect bare filename matches, skipping any that overlap with existing matches
        if let regex = bareFilenameRegex {
            let occupiedRanges: [NSRange] = results.map { link -> NSRange in
                switch link {
                case .url(_, let r): return NSRange(r, in: line)
                case .filePath(_, _, _, let r): return NSRange(r, in: line)
                case .gitHash(_, let r): return NSRange(r, in: line)
                }
            }

            for match in regex.matches(in: line, options: [], range: fullRange) {
                let overlaps = occupiedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
                if overlaps { continue }

                if let link = parseFilePathMatch(match, in: line, nsLine: nsLine, cwd: cwd) {
                    results.append(link)
                }
            }
        }

        return results
    }

    // MARK: - Match Helpers

    /// Finds the first regex match whose range contains the given column.
    private static func findMatch(
        regex: NSRegularExpression?,
        in line: String,
        nsRange: NSRange,
        at column: Int
    ) -> NSTextCheckingResult? {
        guard let regex else { return nil }

        let matches = regex.matches(in: line, options: [], range: nsRange)
        return matches.first { match in
            let range = match.range
            return column >= range.location && column < range.location + range.length
        }
    }

    /// Extracts path, line, and column from a file path regex match.
    /// Validates that the path exists on disk before returning.
    private static func parseFilePathMatch(
        _ match: NSTextCheckingResult,
        in line: String,
        nsLine: NSString,
        cwd: String?
    ) -> DetectedLink? {
        let fullMatch = nsLine.substring(with: match.range)
        guard let range = Range(match.range, in: line) else { return nil }

        // Extract the raw path (strip :line:col suffix)
        var rawPath = fullMatch
        var lineNumber: Int?
        var colNumber: Int?

        // Parse :col (capture group 2)
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
            colNumber = Int(nsLine.substring(with: match.range(at: 2)))
        }

        // Parse :line (capture group 1)
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
            lineNumber = Int(nsLine.substring(with: match.range(at: 1)))
            // Strip the :line:col suffix from the path
            if let colonRange = rawPath.range(of: ":\(lineNumber!)") {
                rawPath = String(rawPath[rawPath.startIndex..<colonRange.lowerBound])
            }
        }

        // Resolve the path
        guard let resolvedPath = resolvePath(rawPath, cwd: cwd) else { return nil }

        // Validate file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else { return nil }

        return .filePath(path: resolvedPath, line: lineNumber, col: colNumber, range: range)
    }

    // MARK: - Path Resolution

    /// Resolves a raw path string to an absolute path.
    /// Expands `~` to home directory. Resolves relative paths (`./`, `../`, and bare)
    /// against the provided CWD.
    private static func resolvePath(_ rawPath: String, cwd: String?) -> String? {
        if rawPath.hasPrefix("~/") {
            return NSString(string: rawPath).expandingTildeInPath
        } else if rawPath.hasPrefix("/") {
            return rawPath
        } else {
            // Relative path: ./..., ../..., or bare (research/file.md)
            guard let cwd else { return nil }
            let baseURL = URL(fileURLWithPath: cwd)
            let resolved = baseURL.appendingPathComponent(rawPath).standardized
            return resolved.path
        }
    }

    // MARK: - Git Hash Detection

    /// Matches git short hashes (7–12 hex chars) at word boundaries.
    /// Excludes matches that are purely numeric (e.g. "1234567") to reduce false positives.
    private static let gitHashPattern: String =
        #"\b[a-f0-9]{7,12}\b"#

    /// Compiled regex for git hash detection.
    private static let gitHashRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: gitHashPattern, options: [])
    }()

    /// Finds all links on a line, including git hashes.
    /// Used by hints mode to scan for all actionable patterns in terminal output.
    /// URLs take priority over file paths; both take priority over git hashes.
    static func detectAllPatterns(in line: String, cwd: String?) -> [DetectedLink] {
        var results = detectAll(in: line, cwd: cwd)

        // Collect occupied ranges to avoid overlapping with existing matches
        let occupiedRanges: [NSRange] = results.compactMap { link in
            let range: Range<String.Index>
            switch link {
            case .url(_, let r): range = r
            case .filePath(_, _, _, let r): range = r
            case .gitHash(_, let r): range = r
            }
            return NSRange(range, in: line)
        }

        // Add git hashes that don't overlap with existing matches
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        if let regex = gitHashRegex {
            for match in regex.matches(in: line, options: [], range: fullRange) {
                let overlaps = occupiedRanges.contains {
                    NSIntersectionRange($0, match.range).length > 0
                }
                if overlaps { continue }

                let hashStr = nsLine.substring(with: match.range)
                // Reject purely numeric strings — real git hashes contain [a-f]
                if hashStr.allSatisfy({ $0.isNumber }) { continue }

                if let range = Range(match.range, in: line) {
                    results.append(.gitHash(hashStr, range: range))
                }
            }
        }

        return results
    }

    // MARK: - Column Range (for hover underlines)

    /// Returns the character column range (start, length) of a detected link.
    /// Used by the overlay view to position the underline correctly.
    static func columnRange(for link: DetectedLink, in line: String) -> (start: Int, length: Int)? {
        let range: Range<String.Index>
        switch link {
        case .url(_, let r): range = r
        case .filePath(_, _, _, let r): range = r
        case .gitHash(_, let r): range = r
        }

        let nsRange = NSRange(range, in: line)
        guard nsRange.location != NSNotFound else { return nil }
        return (start: nsRange.location, length: nsRange.length)
    }

    // MARK: - Raw Text Extraction

    /// Returns the display text of a detected link (the matched string).
    static func text(for link: DetectedLink) -> String {
        switch link {
        case .url(let str, _): return str
        case .filePath(let path, let line, let col, _):
            var result = path
            if let l = line { result += ":\(l)" }
            if let c = col { result += ":\(c)" }
            return result
        case .gitHash(let hash, _): return hash
        }
    }
}
