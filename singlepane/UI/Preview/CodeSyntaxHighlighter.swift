// CodeSyntaxHighlighter.swift
// Applies syntax highlighting to source code in an NSTextView.
// Also provides HTML span generation for markdown code block rendering.
// Supports JSON, YAML, TOML, XML, Swift, JS/TS, Python, Ruby, Rust, Go, C/C++, SQL, Shell, and more.
// Colors are derived from the active theme's ANSI palette for consistency with the terminal.

import AppKit

/// Protocol shared by all syntax highlighters so the editor can swap between them.
@MainActor
protocol SyntaxHighlighting: AnyObject {
    func highlightAll()

    /// Highlights only the given character range. Used for incremental highlighting
    /// of large files where highlighting the full text would be too slow.
    func highlightRange(_ range: NSRange)
}

/// Default: fall back to full highlighting when range highlighting isn't implemented.
extension SyntaxHighlighting {
    func highlightRange(_ range: NSRange) {
        highlightAll()
    }
}

@MainActor
final class CodeSyntaxHighlighter: NSObject, NSTextStorageDelegate, SyntaxHighlighting {

    // MARK: - Properties

    private weak var textView: NSTextView?

    /// The language identifier used to select regex patterns.
    var language: String = "text" {
        didSet {
            if language != oldValue { cachedRegexes = nil }
        }
    }

    /// Cached compiled regex patterns for the current language.
    /// Avoids recompiling NSRegularExpression on every highlightAll() call — a measurable
    /// cost when highlighting is triggered on every scroll in mmap mode.
    private var cachedRegexes: [(regex: NSRegularExpression, colorIndex: Int, isItalic: Bool)]?

    // MARK: - Init

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        textView.textStorage?.delegate = self
    }

    /// When true, uses incremental (range-only) highlighting on edits.
    /// Set by the editor for files ≥1MB to avoid full-text regex passes on every keystroke.
    var incrementalMode = false

    // MARK: - NSTextStorageDelegate

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Capture values before crossing isolation boundary — don't capture textStorage itself
        let isIncremental = MainActor.assumeIsolated { self.incrementalMode }
        let editLocation = editedRange.location
        let editLength = editedRange.length
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isIncremental, let ts = self.textView?.textStorage {
                let start = max(0, editLocation - 200)
                let maxLen = ts.length - start
                let len = min(editLength + 400, maxLen)
                self.highlightRange(NSRange(location: start, length: max(0, len)))
            } else {
                self.highlightAll()
            }
        }
    }

    // MARK: - Regex Cache

    /// Returns compiled regex patterns for the current language, building and caching them
    /// on first access. Avoids recompiling NSRegularExpression on every highlight pass.
    private func compiledPatterns() -> [(regex: NSRegularExpression, colorIndex: Int, isItalic: Bool)] {
        if let cached = cachedRegexes { return cached }
        let patterns = Self.patterns(for: language)
        let compiled = patterns.compactMap { (pattern, colorIndex, isItalic)
            -> (regex: NSRegularExpression, colorIndex: Int, isItalic: Bool)? in
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.anchorsMatchLines]
            ) else { return nil }
            return (regex: regex, colorIndex: colorIndex, isItalic: isItalic)
        }
        cachedRegexes = compiled
        return compiled
    }

    // MARK: - Highlighting

    func highlightAll() {
        guard let textStorage = textView?.textStorage else { return }
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let theme = ThemeManager.shared.activeTheme
        let baseFont = FontManager.shared.activeFont

        // Reset to base style
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: theme.foregroundColor,
        ], range: fullRange)

        // Apply language-specific patterns (cached, not recompiled)
        let compiled = compiledPatterns()
        for (regex, colorIndex, isItalic) in compiled {
            let color = Self.themeColor(at: colorIndex, theme: theme)
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if isItalic {
                let italicFont = NSFont(
                    descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic),
                    size: baseFont.pointSize
                ) ?? baseFont
                attrs[.font] = italicFont
            }
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                textStorage.addAttributes(attrs, range: matchRange)
            }
        }

        textStorage.endEditing()
    }

    /// Highlights only the specified character range. Expands the range to full line
    /// boundaries to avoid partial-line artifacts from multi-line patterns.
    func highlightRange(_ range: NSRange) {
        guard let textStorage = textView?.textStorage else { return }
        let text = textStorage.string as NSString
        guard range.location < text.length else { return }

        // Expand to full line boundaries for correct multi-line pattern matching
        let expandedRange = text.lineRange(for: range)
        guard expandedRange.length > 0 else { return }

        let theme = ThemeManager.shared.activeTheme
        let baseFont = FontManager.shared.activeFont

        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: theme.foregroundColor,
        ], range: expandedRange)

        let compiled = compiledPatterns()
        let substring = text.substring(with: expandedRange)
        for (regex, colorIndex, isItalic) in compiled {
            let color = Self.themeColor(at: colorIndex, theme: theme)
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if isItalic {
                let italicFont = NSFont(
                    descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic),
                    size: baseFont.pointSize
                ) ?? baseFont
                attrs[.font] = italicFont
            }
            let substringRange = NSRange(location: 0, length: (substring as NSString).length)
            regex.enumerateMatches(in: substring, range: substringRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                // Offset match range back to text storage coordinates
                let absoluteRange = NSRange(
                    location: matchRange.location + expandedRange.location,
                    length: matchRange.length
                )
                textStorage.addAttributes(attrs, range: absoluteRange)
            }
        }

        textStorage.endEditing()
    }

    // MARK: - Color Mapping

    /// Maps semantic color indices to theme colors.
    /// 0=comment(dimmed), 1=string(green), 2=keyword(magenta), 3=number(cyan), 4=key(yellow)
    private static func themeColor(at index: Int, theme: Theme) -> NSColor {
        switch index {
        case 0: theme.chromeTextSecondary          // comment
        case 1: theme.paletteColor(at: 2)          // string → green
        case 2: theme.paletteColor(at: 5)          // keyword → magenta
        case 3: theme.paletteColor(at: 6)          // number → cyan
        case 4: theme.paletteColor(at: 3)          // key → yellow
        default: theme.foregroundColor
        }
    }

    // MARK: - Language Detection

    /// Maps a file extension to a language identifier.
    static func language(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "json", "geojson", "har":          "json"
        case "yaml", "yml":                     "yaml"
        case "toml":                            "toml"
        case "xml", "svg", "xib", "storyboard": "xml"
        case "plist":                           "xml"
        case "html", "htm":                     "html"
        case "css":                             "css"
        case "swift":                           "swift"
        case "js", "mjs", "cjs", "jsx":         "js"
        case "ts", "tsx":                       "js"
        case "py":                              "python"
        case "rb":                              "ruby"
        case "rs":                              "rust"
        case "go":                              "go"
        case "sh", "bash", "zsh", "fish":       "shell"
        case "conf", "cfg", "ini", "env":       "shell"
        case "sql":                             "sql"
        case "c", "h":                          "c"
        case "cpp", "cc", "cxx", "hpp":         "c"
        case "java", "kt", "kts":              "java"
        case "cs":                              "csharp"
        case "lua":                             "lua"
        case "vue", "svelte", "astro":          "sfc"
        case "dockerfile":                      "shell"
        case "makefile", "mk":                  "shell"
        case "md", "markdown":                  "markdown"
        default:                                "text"
        }
    }

    /// Maps a full filename (e.g. "Makefile", ".env.example") to a language identifier.
    /// Falls back to extension-based lookup, then returns "text" for unknown files.
    static func language(forFilename filename: String) -> String {
        let lower = filename.lowercased()

        // Exact filename matches for extensionless files
        switch lower {
        case "makefile", "gnumakefile":         return "shell"
        case "dockerfile":                      return "shell"
        case "rakefile", "gemfile", "podfile":  return "ruby"
        case "procfile":                        return "shell"
        case "vagrantfile":                     return "ruby"
        case "justfile":                        return "shell"
        default: break
        }

        // Dotfiles and compound extensions (e.g. ".env.example", ".gitignore")
        if lower.hasPrefix(".env") { return "shell" }
        if lower.hasPrefix(".git") { return "shell" }
        if lower.hasPrefix(".bash") || lower.hasPrefix(".zsh") { return "shell" }
        if lower.hasSuffix(".lock") { return "json" }

        // Fall back to extension-based lookup
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty {
            let result = language(for: ext)
            if result != "text" { return result }
        }

        return "text"
    }

    // MARK: - Patterns

    /// Returns (regex, colorIndex, isItalic) tuples for syntax highlighting.
    /// Color indices: 0=comment, 1=string, 2=keyword, 3=number, 4=key
    /// Used by both NSTextStorage highlighting and HTML span generation.
    nonisolated static func patterns(for language: String) -> [(String, Int, Bool)] {
        switch language {
        case "json":
            return [
                (#""[^"]*?"\s*:"#, 4, false),           // "key":
                (#""[^"]*?""#, 1, false),                 // "string value"
                (#"\b(true|false|null)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "yaml":
            return [
                (#"#.*$"#, 0, true),
                (#"^[\w][\w\s]*?:"#, 4, false),
                (#"^\s+[\w][\w\s]*?:"#, 4, false),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(true|false|null|yes|no)\b"#, 2, false),
                (#"\b-?\d+\.?\d*\b"#, 3, false),
            ]
        case "toml":
            return [
                (#"#.*$"#, 0, true),
                (#"\[[\w\.\-]+\]"#, 4, false),
                (#"^\w[\w\-]*\s*="#, 4, false),
                (#""[^"]*?""#, 1, false),
                (#"\b(true|false)\b"#, 2, false),
                (#"\b-?\d+\.?\d*\b"#, 3, false),
            ]
        case "xml", "html":
            return [
                (#"<!--[\s\S]*?-->"#, 0, true),
                // Strings (attribute values) — applied early, overridden by tag names below
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                // Tag names only: <div, </span, <my-component (not the whole tag)
                (#"</?[A-Za-z][\w\-\.]*"#, 2, false),
                (#"/>"#, 2, false),
                // Attribute names (word before =)
                (#"(?<=\s)[a-zA-Z][\w\-:]*(?=\s*=)"#, 4, false),
            ]
        case "css":
            return [
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"[.#][\w\-]+"#, 4, false),            // selectors
                (#"\b-?\d+\.?\d*(px|em|rem|%|vh|vw)?\b"#, 3, false),
            ]
        case "swift":
            return [
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"\b(func|let|var|if|else|guard|for|while|return|switch|case|break|continue|import|struct|class|enum|protocol|extension|self|Self|where|in|do|try|catch|throw|throws|async|await|public|private|internal|static|final|override|init|deinit|typealias|associatedtype|subscript|lazy|weak|unowned|mutating|nonmutating|convenience|required|optional|some|any|actor|nonisolated|isolated|consuming|borrowing|sending)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "js":
            return [
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"`[^`]*?`"#, 1, false),
                (#"\b(const|let|var|function|return|if|else|for|while|class|import|export|from|default|async|await|try|catch|throw|new|this|typeof|instanceof|switch|case|break|continue|yield|of|in|type|interface|extends|implements)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "python":
            return [
                (#"#.*$"#, 0, true),
                (#"\"\"\"[\s\S]*?\"\"\""#, 1, false),
                (#"'''[\s\S]*?'''"#, 1, false),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|raise|with|yield|lambda|pass|break|continue|and|or|not|in|is|None|True|False|self|async|await)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "ruby":
            return [
                (#"#.*$"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(def|end|class|module|if|elsif|else|unless|while|until|for|do|begin|rescue|ensure|raise|return|yield|require|include|attr_accessor|attr_reader|attr_writer|self|nil|true|false)\b"#, 2, false),
                (#"\b-?\d+\.?\d*\b"#, 3, false),
            ]
        case "rust":
            return [
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"\b(fn|let|mut|const|if|else|for|while|loop|return|match|struct|enum|impl|trait|pub|mod|use|self|Self|where|in|as|ref|move|async|await|unsafe|extern|crate|type|static|dyn|break|continue)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "go":
            return [
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"`[^`]*?`"#, 1, false),
                (#"\b(func|var|const|if|else|for|range|return|switch|case|break|continue|import|package|struct|interface|type|map|chan|select|go|defer|fallthrough|default|nil|true|false)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#, 3, false),
            ]
        case "c", "csharp", "java":
            return [
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(if|else|for|while|do|return|switch|case|break|continue|struct|class|enum|interface|public|private|protected|static|final|override|virtual|abstract|void|int|float|double|char|bool|string|var|const|new|this|null|true|false|try|catch|throw|throws|import|package|namespace|using|include|define|typedef|sizeof|extern|volatile|register|unsigned|signed|long|short)\b"#, 2, false),
                (#"\b-?\d+\.?\d*([eE][+-]?\d+)?[fFlLuU]?\b"#, 3, false),
            ]
        case "shell":
            return [
                (#"#.*$"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|exit|export|source|alias|local|readonly)\b"#, 2, false),
                (#"\$\{?\w+\}?"#, 3, false),
            ]
        case "sql":
            return [
                (#"--.*$"#, 0, true),
                (#"'[^']*?'"#, 1, false),
                (#"(?i)\b(SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TABLE|INDEX|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|SET|VALUES|INTO|DISTINCT|COUNT|SUM|AVG|MAX|MIN|BETWEEN|LIKE|EXISTS|CASE|WHEN|THEN|ELSE|END|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|CHECK|UNIQUE)\b"#, 2, false),
                (#"\b-?\d+\.?\d*\b"#, 3, false),
            ]
        case "lua":
            return [
                (#"--.*$"#, 0, true),
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"\b(function|end|if|then|else|elseif|for|while|do|repeat|until|return|local|and|or|not|in|nil|true|false|require)\b"#, 2, false),
                (#"\b-?\d+\.?\d*\b"#, 3, false),
            ]

        // Single-file component formats (.vue, .svelte, .astro).
        // Merges HTML, JS/TS, and CSS patterns into one composite set.
        // Last-match-wins: later patterns override earlier ones where they
        // overlap. Order: comments → strings → tag names → self-close →
        // attribute names → vue directives → CSS selectors → JS keywords → numbers.
        // This gives four distinct colors: tag names (magenta), attribute
        // names (yellow), attribute values/strings (green), numbers (cyan).
        case "sfc":
            return [
                // Comments — HTML, JS, CSS
                (#"<!--[\s\S]*?-->"#, 0, true),
                (#"//.*$"#, 0, true),
                (#"/\*[\s\S]*?\*/"#, 0, true),

                // Strings — JS (double, single, template) and HTML attribute values
                (#""[^"]*?""#, 1, false),
                (#"'[^']*?'"#, 1, false),
                (#"`[^`]*?`"#, 1, false),

                // HTML tag names only: <template, </div, <HeroSection
                // Does NOT consume attributes — just the bracket + name.
                (#"</?[A-Za-z][\w\-\.]*"#, 2, false),

                // Self-closing />
                (#"/>"#, 2, false),

                // HTML/Vue attribute names (word before =): heading=, class=
                (#"(?<=\s)[a-zA-Z@:v][\w\-:\.]*(?=\s*=)"#, 4, false),

                // Vue directives without a value: v-else, v-cloak, v-pre
                (#"(?<=\s)v-[\w\-]+"#, 4, false),

                // CSS selectors
                (#"[.#][\w\-]+"#, 4, false),

                // JS/TS keywords (superset covering both)
                (#"\b(const|let|var|function|return|if|else|for|while|class|import|export|from|default|async|await|try|catch|throw|new|this|typeof|instanceof|switch|case|break|continue|yield|of|in|type|interface|extends|implements)\b"#, 2, false),

                // Numbers — JS and CSS units
                (#"\b-?\d+\.?\d*(px|em|rem|%|vh|vw)?([eE][+-]?\d+)?\b"#, 3, false),
            ]
        default:
            return []
        }
    }

    // MARK: - Language Tag Mapping

    /// Maps markdown fenced code block language tags to internal language identifiers.
    /// Markdown uses full names (e.g., "javascript", "typescript") while our patterns
    /// use shorter IDs (e.g., "js"). Tags that already match a language ID pass through.
    nonisolated static func languageFromTag(_ tag: String) -> String {
        let normalized = tag.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        // Direct matches — these already map to our language IDs
        case "json", "yaml", "toml", "xml", "html", "css", "swift",
             "js", "python", "ruby", "rust", "go", "c", "sql", "lua",
             "shell", "java", "csharp":
            return normalized

        // Aliases — common markdown tags that differ from our IDs
        case "javascript", "jsx":               return "js"
        case "typescript", "tsx", "ts":          return "js"
        case "bash", "sh", "zsh", "fish":       return "shell"
        case "dockerfile", "makefile":          return "shell"
        case "cpp", "c++", "cc", "cxx",
             "hpp", "h", "objective-c", "objc": return "c"
        case "vue", "svelte", "astro":           return "sfc"
        case "yml":                             return "yaml"
        case "htm":                             return "html"
        case "py", "python3":                   return "python"
        case "rb":                              return "ruby"
        case "rs":                              return "rust"
        case "golang":                          return "go"
        case "kt", "kotlin":                    return "java"
        case "cs", "c#":                        return "csharp"
        case "jsonc", "json5":                  return "json"
        case "svg", "xib", "plist":             return "xml"
        case "ini", "conf", "cfg", "env":       return "shell"
        default:                                return normalized
        }
    }

    // MARK: - HTML Span Generation

    /// CSS class names for each color index, matching the classes in the HTML template.
    /// 0=comment, 1=string, 2=keyword, 3=number, 4=key
    nonisolated private static let cssClassNames = [
        "syn-comment", "syn-string", "syn-keyword", "syn-number", "syn-key",
    ]

    /// Generates syntax-highlighted HTML for a code string.
    /// Runs the same regex patterns used for NSTextView highlighting, but wraps
    /// matched tokens in `<span class="syn-*">` elements instead of applying attributes.
    /// Returns plain HTML-escaped text if the language has no patterns.
    ///
    /// Overlap resolution: last-match-wins, consistent with the NSTextStorage approach
    /// where later patterns overwrite earlier attributes.
    nonisolated static func highlightToHTML(code: String, language: String) -> String {
        let lang = languageFromTag(language)
        let pats = patterns(for: lang)

        // No patterns → return plain escaped text
        guard !pats.isEmpty else { return escapeHTMLForCode(code) }

        let nsCode = code as NSString
        let length = nsCode.length
        guard length > 0 else { return "" }

        // Per-character color index: -1 means no highlight (plain text).
        // Later patterns overwrite earlier ones (last-match-wins).
        var colorMap = [Int](repeating: -1, count: length)

        for (pattern, colorIndex, _) in pats {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.anchorsMatchLines]
            ) else { continue }

            regex.enumerateMatches(
                in: code,
                range: NSRange(location: 0, length: length)
            ) { match, _, _ in
                guard let range = match?.range else { return }
                let end = range.location + range.length
                for i in range.location..<end {
                    colorMap[i] = colorIndex
                }
            }
        }

        // Build HTML by grouping consecutive characters with the same color index
        // into runs, wrapping colored runs in <span> elements.
        var html = ""
        var runStart = 0

        while runStart < length {
            let currentColor = colorMap[runStart]
            var runEnd = runStart + 1
            while runEnd < length && colorMap[runEnd] == currentColor {
                runEnd += 1
            }

            let runText = nsCode.substring(with: NSRange(location: runStart, length: runEnd - runStart))
            let escaped = escapeHTMLForCode(runText)

            if currentColor >= 0 && currentColor < cssClassNames.count {
                html += "<span class=\"\(cssClassNames[currentColor])\">\(escaped)</span>"
            } else {
                html += escaped
            }

            runStart = runEnd
        }

        return html
    }

    /// HTML-escapes text for use inside `<pre><code>` blocks.
    nonisolated private static func escapeHTMLForCode(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
