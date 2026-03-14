// BracketMatcher.swift
// Finds matching bracket pairs and HTML/XML tag pairs given a cursor position.
//
// Bracket matching: supports `{}`, `[]`, `()`. Scans forward for opening
// brackets, backward for closing brackets, using a depth counter.
//
// Tag matching: for HTML/XML files, matches `<div>` to `</div>` style pairs.
// Highlights the tag name in both the opening and closing tags.
//
// Used by EditorViewController to highlight matches when the cursor
// is adjacent to a bracket or inside an HTML/XML tag.

import Foundation

/// The result of a bracket match query (single-character pairs).
struct BracketMatchResult {

    /// Index of the bracket character adjacent to the cursor.
    let bracketIndex: Int

    /// Index of the matching bracket, or nil if unbalanced.
    let matchIndex: Int?
}

/// The result of an HTML/XML tag match query (range-based).
struct TagMatchResult {

    /// Range of the tag name at the cursor (e.g. "div" in `<div>`).
    let tagNameRange: NSRange

    /// Range of the matching tag name, or nil if unmatched.
    let matchTagNameRange: NSRange?
}

/// Stateless bracket and tag matching utility.
enum BracketMatcher {

    // MARK: - Bracket Pairs

    private static let openBrackets: Set<Character> = ["{", "[", "("]
    private static let closeBrackets: Set<Character> = ["}", "]", ")"]

    /// Maps each opening bracket to its closing counterpart.
    private static let matchingClose: [Character: Character] = [
        "{": "}", "[": "]", "(": ")",
    ]

    /// Maps each closing bracket to its opening counterpart.
    private static let matchingOpen: [Character: Character] = [
        "}": "{", "]": "[", ")": "(",
    ]

    // MARK: - Bracket Matching

    /// Finds a bracket adjacent to `cursorPosition` and locates its match.
    ///
    /// Checks the character *at* cursorPosition first (the character to the
    /// right of the cursor), then the character *before* cursorPosition
    /// (the character to the left). This matches VS Code / Sublime behavior
    /// where the match triggers from either side of a bracket.
    ///
    /// - Parameters:
    ///   - text: The full document text.
    ///   - cursorPosition: The insertion point index (0-based character offset).
    /// - Returns: A `BracketMatchResult` if a bracket is adjacent, nil otherwise.
    static func findMatch(in text: String, cursorPosition: Int) -> BracketMatchResult? {
        let chars = Array(text.utf16)
        let length = chars.count

        // Check character at cursor position (right side)
        if cursorPosition < length {
            let ch = Character(UnicodeScalar(chars[cursorPosition])!)
            if let result = matchBracketAt(index: cursorPosition, character: ch, in: chars) {
                return result
            }
        }

        // Check character before cursor position (left side)
        if cursorPosition > 0 && cursorPosition <= length {
            let ch = Character(UnicodeScalar(chars[cursorPosition - 1])!)
            if let result = matchBracketAt(index: cursorPosition - 1, character: ch, in: chars) {
                return result
            }
        }

        return nil
    }

    // MARK: - HTML/XML Tag Matching

    /// Languages where tag matching is enabled.
    /// Includes "sfc" for single-file component formats (.vue, .svelte, .astro)
    /// which contain HTML markup alongside JS and CSS.
    private static let tagMatchLanguages: Set<String> = ["html", "xml", "sfc"]

    /// Finds the HTML/XML tag containing `cursorPosition` and locates its matching
    /// opening or closing counterpart.
    ///
    /// - Parameters:
    ///   - text: The full document text (as NSString for range compatibility).
    ///   - cursorPosition: The insertion point index.
    ///   - language: The syntax language identifier.
    /// - Returns: A `TagMatchResult` if the cursor is inside a tag, nil otherwise.
    static func findTagMatch(
        in text: NSString,
        cursorPosition: Int,
        language: String
    ) -> TagMatchResult? {
        guard tagMatchLanguages.contains(language) else { return nil }

        let length = text.length
        guard cursorPosition <= length else { return nil }

        // Find the tag surrounding the cursor by scanning for < and >
        guard let tagInfo = parseTagAtCursor(in: text, cursor: cursorPosition) else {
            return nil
        }

        // Self-closing tags (e.g. <br/>) have no counterpart
        guard !tagInfo.isSelfClosing else { return nil }

        let tagNameRange = tagInfo.nameRange

        if tagInfo.isClosing {
            // Closing tag — scan backward for the matching opening tag
            let matchRange = scanForOpeningTag(
                named: tagInfo.name, in: text, before: tagInfo.tagStart
            )
            return TagMatchResult(tagNameRange: tagNameRange, matchTagNameRange: matchRange)
        } else {
            // Opening tag — scan forward for the matching closing tag
            let matchRange = scanForClosingTag(
                named: tagInfo.name, in: text, after: tagInfo.tagEnd
            )
            return TagMatchResult(tagNameRange: tagNameRange, matchTagNameRange: matchRange)
        }
    }

    // MARK: - Private (Bracket Matching)

    /// Attempts a bracket match at a specific index.
    private static func matchBracketAt(
        index: Int,
        character: Character,
        in chars: [UTF16.CodeUnit]
    ) -> BracketMatchResult? {
        if openBrackets.contains(character) {
            let closeChar = matchingClose[character]!
            let matchIdx = scanForward(
                from: index, open: character, close: closeChar, in: chars
            )
            return BracketMatchResult(bracketIndex: index, matchIndex: matchIdx)
        }

        if closeBrackets.contains(character) {
            let openChar = matchingOpen[character]!
            let matchIdx = scanBackward(
                from: index, open: openChar, close: character, in: chars
            )
            return BracketMatchResult(bracketIndex: index, matchIndex: matchIdx)
        }

        return nil
    }

    /// Scans forward from an opening bracket to find its closing match.
    private static func scanForward(
        from index: Int,
        open: Character,
        close: Character,
        in chars: [UTF16.CodeUnit]
    ) -> Int? {
        let openCode = open.utf16First
        let closeCode = close.utf16First
        var depth = 1
        var i = index + 1

        while i < chars.count {
            if chars[i] == openCode {
                depth += 1
            } else if chars[i] == closeCode {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }

        return nil
    }

    /// Scans backward from a closing bracket to find its opening match.
    private static func scanBackward(
        from index: Int,
        open: Character,
        close: Character,
        in chars: [UTF16.CodeUnit]
    ) -> Int? {
        let openCode = open.utf16First
        let closeCode = close.utf16First
        var depth = 1
        var i = index - 1

        while i >= 0 {
            if chars[i] == closeCode {
                depth += 1
            } else if chars[i] == openCode {
                depth -= 1
                if depth == 0 { return i }
            }
            i -= 1
        }

        return nil
    }

    // MARK: - Private (Tag Matching)

    /// Parsed information about an HTML/XML tag.
    private struct TagInfo {
        let name: String          // e.g. "div", "span"
        let nameRange: NSRange    // range of the tag name in the document
        let tagStart: Int         // index of the `<` character
        let tagEnd: Int           // index after the `>` character
        let isClosing: Bool       // true for `</div>`
        let isSelfClosing: Bool   // true for `<br/>` or `<img />`
    }

    /// Finds and parses the HTML/XML tag surrounding the cursor position.
    /// Returns nil if the cursor is not inside a tag.
    private static func parseTagAtCursor(in text: NSString, cursor: Int) -> TagInfo? {
        let length = text.length

        // Scan backward from cursor to find `<`
        var openAngle = cursor
        while openAngle > 0 {
            openAngle -= 1
            let ch = text.character(at: openAngle)
            if ch == unicharLessThan {
                break
            }
            // Hit a `>` before finding `<` — cursor is not inside a tag
            if ch == unicharGreaterThan && openAngle < cursor - 1 {
                return nil
            }
        }
        guard text.character(at: openAngle) == unicharLessThan else { return nil }

        // Scan forward from openAngle to find `>`
        var closeAngle = openAngle + 1
        while closeAngle < length {
            if text.character(at: closeAngle) == unicharGreaterThan {
                break
            }
            closeAngle += 1
        }
        guard closeAngle < length else { return nil }

        // Verify cursor is within this tag
        guard cursor >= openAngle && cursor <= closeAngle + 1 else { return nil }

        let tagContent = text.substring(
            with: NSRange(location: openAngle, length: closeAngle - openAngle + 1)
        )

        // Parse tag name using regex: matches <tagname or </tagname
        // Also detects self-closing /> at the end
        guard let regex = try? NSRegularExpression(
            pattern: #"^<(/?)([a-zA-Z][a-zA-Z0-9\-]*)"#
        ) else { return nil }

        let tagNS = tagContent as NSString
        guard let match = regex.firstMatch(
            in: tagContent,
            range: NSRange(location: 0, length: tagNS.length)
        ) else { return nil }

        let slashRange = match.range(at: 1)
        let isClosing = slashRange.length > 0

        let nameLocalRange = match.range(at: 2)
        let name = tagNS.substring(with: nameLocalRange)

        // Convert name range to document coordinates
        let nameRange = NSRange(
            location: openAngle + nameLocalRange.location,
            length: nameLocalRange.length
        )

        let isSelfClosing = tagContent.hasSuffix("/>")

        return TagInfo(
            name: name,
            nameRange: nameRange,
            tagStart: openAngle,
            tagEnd: closeAngle + 1,
            isClosing: isClosing,
            isSelfClosing: isSelfClosing
        )
    }

    /// Scans forward from `startIndex` to find the matching closing tag `</name>`.
    /// Handles nesting by counting opening/closing tags with the same name.
    private static func scanForClosingTag(
        named name: String,
        in text: NSString,
        after startIndex: Int
    ) -> NSRange? {
        let length = text.length
        var depth = 1
        var i = startIndex

        while i < length - 1 {
            // Look for `<`
            if text.character(at: i) == unicharLessThan {
                // Try to parse a tag at this position
                if let tag = parseTagStartingAt(i, named: name, in: text) {
                    if tag.isSelfClosing {
                        // Self-closing tags don't affect depth
                    } else if tag.isClosing {
                        depth -= 1
                        if depth == 0 { return tag.nameRange }
                    } else {
                        depth += 1
                    }
                    i = tag.tagEnd
                    continue
                }
            }
            i += 1
        }

        return nil
    }

    /// Scans backward from `startIndex` to find the matching opening tag `<name>`.
    /// Handles nesting by counting opening/closing tags with the same name.
    private static func scanForOpeningTag(
        named name: String,
        in text: NSString,
        before startIndex: Int
    ) -> NSRange? {
        var depth = 1
        var i = startIndex - 1

        while i >= 0 {
            // Look for `>` — we scan backward, so we find the end of a tag first
            if text.character(at: i) == unicharGreaterThan {
                // Scan backward from `>` to find the `<` of this tag
                var tagStart = i - 1
                while tagStart >= 0 && text.character(at: tagStart) != unicharLessThan {
                    tagStart -= 1
                }
                if tagStart >= 0 {
                    if let tag = parseTagStartingAt(tagStart, named: name, in: text) {
                        if tag.isSelfClosing {
                            // Self-closing tags don't affect depth
                        } else if tag.isClosing {
                            depth += 1
                        } else {
                            depth -= 1
                            if depth == 0 { return tag.nameRange }
                        }
                        i = tagStart - 1
                        continue
                    }
                }
            }
            i -= 1
        }

        return nil
    }

    /// Parses a tag starting at `index` if it matches the given `name`.
    /// Returns nil if the tag at this position has a different name.
    private static func parseTagStartingAt(
        _ index: Int,
        named name: String,
        in text: NSString
    ) -> TagInfo? {
        let length = text.length
        guard index < length, text.character(at: index) == unicharLessThan else { return nil }

        // Find the closing `>`
        var closeAngle = index + 1
        while closeAngle < length {
            if text.character(at: closeAngle) == unicharGreaterThan { break }
            closeAngle += 1
        }
        guard closeAngle < length else { return nil }

        let tagContent = text.substring(
            with: NSRange(location: index, length: closeAngle - index + 1)
        )

        guard let regex = try? NSRegularExpression(
            pattern: #"^<(/?)([a-zA-Z][a-zA-Z0-9\-]*)"#
        ) else { return nil }

        let tagNS = tagContent as NSString
        guard let match = regex.firstMatch(
            in: tagContent,
            range: NSRange(location: 0, length: tagNS.length)
        ) else { return nil }

        let parsedName = tagNS.substring(with: match.range(at: 2))
        guard parsedName.caseInsensitiveCompare(name) == .orderedSame else { return nil }

        let slashRange = match.range(at: 1)
        let nameLocalRange = match.range(at: 2)

        return TagInfo(
            name: parsedName,
            nameRange: NSRange(location: index + nameLocalRange.location, length: nameLocalRange.length),
            tagStart: index,
            tagEnd: closeAngle + 1,
            isClosing: slashRange.length > 0,
            isSelfClosing: tagContent.hasSuffix("/>")
        )
    }

    // MARK: - UTF-16 Constants

    private static let unicharLessThan: unichar = 0x3C    // <
    private static let unicharGreaterThan: unichar = 0x3E  // >
}

// MARK: - Character Helper

private extension Character {

    /// Returns the first UTF-16 code unit for this character.
    /// Safe for all ASCII bracket characters.
    var utf16First: UTF16.CodeUnit {
        utf16.first!
    }
}
