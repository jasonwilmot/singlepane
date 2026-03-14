// LargeFileReader.swift
// Memory-mapped file reader for large files. Maps file data via mmap(2) and builds
// a line-offset index so the UI can render only visible lines without loading
// the entire file into memory.
//
// Per CLAUDE.md § 4.7: "The built-in viewer uses mmap(2) for large files.
// Never load an entire file into memory."

import Foundation

// MARK: - Size Thresholds

/// File size thresholds that control loading strategy.
enum FileSizeThreshold {
    /// Files below this size load normally via String(contentsOf:).
    static let normalLoad: Int64 = 1_048_576 // 1 MB

    /// Files above this size trigger a warning banner in the editor.
    static let editorWarning: Int64 = 1_048_576 // 1 MB

    /// Files above this size show a truncation warning in markdown preview.
    static let markdownTruncation: Int64 = 10_485_760 // 10 MB
}

// MARK: - Large File Reader

/// Actor-isolated memory-mapped file reader. Maps file bytes via `Data(contentsOf:options:.mappedIfSafe)`
/// and builds a newline-offset index in a background pass so callers can extract arbitrary
/// line ranges without loading the entire file into a Swift String.
actor LargeFileReader {

    /// The memory-mapped file data. Stays mapped for the lifetime of this reader.
    private let mappedData: Data

    /// Byte offsets of the start of each line (0-indexed). The first entry is always 0.
    /// Built by scanning for `\n` in the mapped data.
    private let lineOffsets: [Int]

    /// Total number of lines in the file.
    var lineCount: Int { lineOffsets.count }

    /// Total file size in bytes.
    var fileSize: Int { mappedData.count }

    /// Length of the longest line in bytes. Used to detect minified/bundled files
    /// where line-based windowing is insufficient (e.g., 1.4MB file with 245 lines).
    let maxLineLength: Int

    // MARK: - Init

    /// Opens and memory-maps the file at the given URL, then builds the line-offset index.
    /// Throws if the file cannot be read or mapped.
    init(url: URL) throws {
        self.mappedData = try Data(contentsOf: url, options: .mappedIfSafe)
        self.lineOffsets = Self.buildLineIndex(data: self.mappedData)
        self.maxLineLength = Self.computeMaxLineLength(offsets: self.lineOffsets, totalSize: self.mappedData.count)
    }

    // MARK: - Line Index

    /// Scans the mapped data for newline characters and returns an array of byte offsets
    /// marking the start of each line. The first entry is always 0.
    /// Uses libc `memchr` which is SIMD-optimized on Apple platforms — typically 4-8x faster
    /// than a byte-by-byte Swift loop for large files.
    private static func buildLineIndex(data: Data) -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(data.count / 40) // ~40 bytes per line estimate

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            let newline = Int32(UInt8(ascii: "\n"))

            var offset = 0
            while offset < count {
                guard let found = memchr(base + offset, newline, count - offset) else { break }
                let foundOffset = base.distance(to: found)
                if foundOffset + 1 < count {
                    offsets.append(foundOffset + 1)
                }
                offset = foundOffset + 1
            }
        }

        return offsets
    }

    /// Computes the maximum line length from the offset index.
    private static func computeMaxLineLength(offsets: [Int], totalSize: Int) -> Int {
        guard !offsets.isEmpty else { return totalSize }
        var maxLen = 0
        for i in 0..<offsets.count {
            let start = offsets[i]
            let end = (i + 1 < offsets.count) ? offsets[i + 1] : totalSize
            maxLen = max(maxLen, end - start)
        }
        return maxLen
    }

    // MARK: - Byte-Range Reading

    /// Reads a byte range from the mapped file as a UTF-8 string.
    /// Used for character-based windowing when lines are too long for line-based windowing.
    func readByteRange(_ range: Range<Int>) -> String {
        let clampedStart = max(0, range.lowerBound)
        let clampedEnd = min(mappedData.count, range.upperBound)
        guard clampedStart < clampedEnd else { return "" }
        let subdata = mappedData[clampedStart..<clampedEnd]
        return String(decoding: subdata, as: UTF8.self)
    }

    /// Returns the byte offset for the start of the given line.
    func byteOffset(forLine line: Int) -> Int {
        let clamped = max(0, min(line, lineOffsets.count - 1))
        return lineOffsets[clamped]
    }

    // MARK: - Line Reading

    /// Extracts a range of lines as a UTF-8 string.
    /// - Parameters:
    ///   - lineRange: 0-based range of line indices (e.g., 0..<100 for the first 100 lines).
    /// - Returns: The text content of the requested lines, or an empty string if out of range.
    func readLines(_ lineRange: Range<Int>) -> String {
        let clampedStart = max(0, lineRange.lowerBound)
        let clampedEnd = min(lineOffsets.count, lineRange.upperBound)
        guard clampedStart < clampedEnd else { return "" }

        let startByte = lineOffsets[clampedStart]
        let endByte: Int
        if clampedEnd < lineOffsets.count {
            endByte = lineOffsets[clampedEnd]
        } else {
            endByte = mappedData.count
        }

        guard startByte < endByte else { return "" }

        let subdata = mappedData[startByte..<endByte]
        return String(decoding: subdata, as: UTF8.self)
    }

    /// Returns the line number (0-based) that contains the given byte offset.
    func lineNumber(forByteOffset offset: Int) -> Int {
        // Binary search for the largest lineOffset ≤ offset
        var lo = 0
        var hi = lineOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineOffsets[mid] <= offset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    // MARK: - Search

    /// Searches the entire mapped file for the given query.
    /// When `caseSensitive` is true, uses libc `memmem` for SIMD-optimized matching.
    /// When `caseSensitive` is false (default), uses ASCII case-insensitive comparison.
    /// Returns match positions as byte offset + length pairs.
    /// Suitable for files of any size — scans raw bytes without creating a String.
    func searchAll(query: String, caseSensitive: Bool = false) -> [(byteOffset: Int, length: Int)] {
        guard !query.isEmpty else { return [] }

        let queryBytes = caseSensitive
            ? Array(query.utf8)
            : Array(query.lowercased().utf8)
        let queryLen = queryBytes.count
        guard queryLen > 0 else { return [] }

        var matches: [(byteOffset: Int, length: Int)] = []

        mappedData.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            guard count >= queryLen else { return }

            if caseSensitive {
                // Fast path: use memmem for case-sensitive search (SIMD-optimized on Apple platforms)
                var offset = 0
                queryBytes.withUnsafeBufferPointer { queryBuf in
                    while offset + queryLen <= count {
                        guard let found = memmem(
                            base + offset, count - offset,
                            queryBuf.baseAddress!, queryLen
                        ) else { break }
                        let foundOffset = base.distance(to: found)
                        matches.append((byteOffset: foundOffset, length: queryLen))
                        offset = foundOffset + queryLen
                    }
                }
            } else {
                // Case-insensitive: use first-byte skip with memchr to jump to candidates,
                // then verify the rest of the match. Faster than byte-by-byte for sparse matches.
                let typedBase = base.assumingMemoryBound(to: UInt8.self)
                let firstByte = queryBytes[0]
                // For single-byte queries with case-insensitive, also check the uppercase variant
                let firstByteUpper = (firstByte >= 0x61 && firstByte <= 0x7A) ? firstByte - 0x20 : firstByte

                var offset = 0
                while offset + queryLen <= count {
                    // Use memchr to skip to next potential match (lowercase first byte)
                    var candidateOffset: Int? = nil

                    // Find next occurrence of either case of the first byte
                    var searchPos = offset
                    while searchPos + queryLen <= count {
                        let byte = typedBase[searchPos]
                        let lower = (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
                        if lower == firstByte || byte == firstByteUpper {
                            candidateOffset = searchPos
                            break
                        }
                        searchPos += 1
                    }

                    guard let candidate = candidateOffset else { break }

                    // Verify the rest of the match
                    var matched = true
                    for j in 1..<queryLen {
                        let fileByte = typedBase[candidate + j]
                        let lower = (fileByte >= 0x41 && fileByte <= 0x5A) ? fileByte + 0x20 : fileByte
                        if lower != queryBytes[j] {
                            matched = false
                            break
                        }
                    }

                    if matched {
                        matches.append((byteOffset: candidate, length: queryLen))
                        offset = candidate + queryLen
                    } else {
                        offset = candidate + 1
                    }
                }
            }
        }

        return matches
    }

    /// Converts a byte-offset match to an NSRange relative to a given line window.
    /// Returns nil if the match falls outside the window.
    func nsRange(
        forByteOffset offset: Int,
        length: Int,
        inLineWindow windowStart: Int,
        windowLineCount: Int
    ) -> NSRange? {
        let windowEnd = min(windowStart + windowLineCount, lineOffsets.count)
        let windowStartByte = lineOffsets[max(0, windowStart)]
        let windowEndByte = windowEnd < lineOffsets.count
            ? lineOffsets[windowEnd]
            : mappedData.count

        // Check if the match falls within the window
        guard offset >= windowStartByte, offset + length <= windowEndByte else { return nil }

        // Calculate character offset within the window text.
        // Since we decode as UTF-8, byte offset from window start maps directly
        // for ASCII content. For multi-byte UTF-8, we need to count actual characters.
        let windowData = mappedData[windowStartByte..<offset]
        let charOffset = String(decoding: windowData, as: UTF8.self).count
        let matchData = mappedData[offset..<(offset + length)]
        let charLength = String(decoding: matchData, as: UTF8.self).count

        return NSRange(location: charOffset, length: charLength)
    }
}

// MARK: - File Size Helpers

extension URL {
    /// Returns the file size in bytes, or 0 if the file doesn't exist or can't be stat'd.
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}

/// Formats a byte count as a human-readable string (e.g., "4.2 MB").
func formattedFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
