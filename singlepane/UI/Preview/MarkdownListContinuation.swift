// MarkdownListContinuation.swift
// Handles auto-continuation of markdown lists on Return, and Tab/Shift+Tab
// indent/un-indent for list items. Used by EditorViewController in markdown mode.
//
// Supported list types:
//   • Unordered: `- `, `* `, `+ `
//   • Ordered: `1. `, `2. `, etc.
//   • Checkbox: `- [ ] `, `- [x] `
//
// Behavior:
//   • Return on a non-empty list line → insert newline + next marker
//   • Return on an empty marker (no content after it) → remove marker, plain newline
//   • Tab on a list line → prepend one indent level (4 spaces)
//   • Shift+Tab on a list line → remove one indent level

import AppKit

/// Indent unit for nested lists (4 spaces, matching standard markdown convention).
private let indentUnit = "    "

// MARK: - List Prefix Detection

/// Describes a parsed markdown list prefix (e.g. "  - [ ] " or "1. ").
struct MarkdownListPrefix {

    /// Leading whitespace (indentation).
    let indent: String

    /// The marker itself (e.g. "- ", "* ", "1. ", "- [ ] ").
    let marker: String

    /// Content after the marker (may be empty for a bare marker line).
    let content: String

    /// The full prefix string: indent + marker.
    var fullPrefix: String { indent + marker }

    /// Returns the marker for the next line in the list.
    /// Ordered lists increment the number; others repeat the same marker.
    var nextMarker: String {
        // Ordered list: extract number and increment
        if let match = marker.range(of: #"^(\d+)\.\s$"#, options: .regularExpression),
           let num = Int(marker[match].dropLast(2)) {
            return "\(num + 1). "
        }
        return marker
    }
}

/// Attempts to parse a markdown list prefix from a line of text.
/// Returns nil if the line is not a list item.
func parseMarkdownListPrefix(_ line: String) -> MarkdownListPrefix? {
    // Match: optional indent, then a list marker, then the rest
    // Checkbox: `- [ ] ` or `- [x] ` (with optional indent)
    // Unordered: `- `, `* `, `+ `
    // Ordered: `1. `, `23. `, etc.
    let patterns: [(regex: String, markerGroup: Int)] = [
        (#"^(\s*)(- \[[x ]\] )(.*)"#, 2),   // Checkbox
        (#"^(\s*)([-*+] )(.*)"#, 2),          // Unordered
        (#"^(\s*)(\d+\. )(.*)"#, 2),          // Ordered
    ]

    for (pattern, markerGroup) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: line,
                  range: NSRange(location: 0, length: (line as NSString).length)
              )
        else { continue }

        let nsLine = line as NSString
        let indent = nsLine.substring(with: match.range(at: 1))
        let marker = nsLine.substring(with: match.range(at: markerGroup))
        let content = nsLine.substring(with: match.range(at: 3))

        return MarkdownListPrefix(indent: indent, marker: marker, content: content)
    }
    return nil
}

// MARK: - Return Key Handling

/// Handles Return key in markdown mode. Returns true if handled, false to pass through.
/// - If the current line has a list marker with content: insert newline + continued marker.
/// - If the current line is a bare marker (no content): delete the marker, insert plain newline.
@MainActor
func handleMarkdownReturn(in textView: NSTextView) -> Bool {
    let text = textView.string as NSString
    let selectedRange = textView.selectedRange()

    // Get the current line
    let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let currentLine = text.substring(with: lineRange)

    // Strip trailing newline for parsing
    let trimmedLine = currentLine.hasSuffix("\n")
        ? String(currentLine.dropLast())
        : currentLine

    guard let prefix = parseMarkdownListPrefix(trimmedLine) else {
        return false // Not a list line — let default behavior handle it
    }

    if prefix.content.trimmingCharacters(in: .whitespaces).isEmpty {
        // Empty marker line → remove the marker and insert a plain newline (break out of list)
        let markerStart = lineRange.location
        let markerLength = (prefix.fullPrefix as NSString).length
        let replaceRange = NSRange(location: markerStart, length: markerLength)

        textView.shouldChangeText(in: replaceRange, replacementString: "\n")
        textView.textStorage?.replaceCharacters(in: replaceRange, with: "\n")
        textView.didChangeText()

        // Position cursor after the newline
        let newCursor = markerStart + 1
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
    } else {
        // Non-empty list line → insert newline + next marker
        let insertion = "\n" + prefix.indent + prefix.nextMarker
        let insertRange = selectedRange

        textView.shouldChangeText(in: insertRange, replacementString: insertion)
        textView.textStorage?.replaceCharacters(in: insertRange, with: insertion)
        textView.didChangeText()

        // Position cursor after the new marker
        let newCursor = insertRange.location + (insertion as NSString).length
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
    }

    return true
}

// MARK: - Tab Indent Handling

/// Handles Tab key in markdown mode. Indents the current line if it's a list item.
/// Returns true if handled, false to pass through.
@MainActor
func handleMarkdownTab(in textView: NSTextView) -> Bool {
    let text = textView.string as NSString
    let selectedRange = textView.selectedRange()
    let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let currentLine = text.substring(with: lineRange)
    let trimmedLine = currentLine.hasSuffix("\n") ? String(currentLine.dropLast()) : currentLine

    guard parseMarkdownListPrefix(trimmedLine) != nil else {
        return false // Not a list line
    }

    // Prepend indent unit at the start of the line
    let insertRange = NSRange(location: lineRange.location, length: 0)
    textView.shouldChangeText(in: insertRange, replacementString: indentUnit)
    textView.textStorage?.replaceCharacters(in: insertRange, with: indentUnit)
    textView.didChangeText()

    // Move cursor forward by the indent width
    let newCursor = selectedRange.location + (indentUnit as NSString).length
    textView.setSelectedRange(NSRange(location: newCursor, length: 0))

    return true
}

/// Handles Shift+Tab key in markdown mode. Un-indents the current line if it's a list item.
/// Returns true if handled, false to pass through.
@MainActor
func handleMarkdownBacktab(in textView: NSTextView) -> Bool {
    let text = textView.string as NSString
    let selectedRange = textView.selectedRange()
    let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let currentLine = text.substring(with: lineRange)
    let trimmedLine = currentLine.hasSuffix("\n") ? String(currentLine.dropLast()) : currentLine

    guard let prefix = parseMarkdownListPrefix(trimmedLine) else {
        return false // Not a list line
    }

    // Only un-indent if there's leading whitespace to remove
    guard !prefix.indent.isEmpty else { return true } // Already at left edge, consume the event

    // Remove up to one indent unit from the start of the line
    let indentLen = (indentUnit as NSString).length
    let removeCount = min(indentLen, (prefix.indent as NSString).length)
    let removeRange = NSRange(location: lineRange.location, length: removeCount)

    textView.shouldChangeText(in: removeRange, replacementString: "")
    textView.textStorage?.replaceCharacters(in: removeRange, with: "")
    textView.didChangeText()

    // Move cursor back by the removed amount
    let newCursor = max(lineRange.location, selectedRange.location - removeCount)
    textView.setSelectedRange(NSRange(location: newCursor, length: 0))

    return true
}
