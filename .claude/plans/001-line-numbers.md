# 001: Line Numbers — Implementation Plan

**Overall Progress:** `100%`

## TLDR
Add a line number gutter to CodePreviewViewController (read-only) and EditorViewController (editable) using NSRulerView. Gutter is theme-aware, font-aware, auto-sizes for digit count, supports click-to-select-line, and shows current line highlight in the editor only.

## Critical Decisions
- **NSRulerView** — use the standard AppKit vertical ruler attached to NSScrollView, not a custom NSView. Auto-scrolls with content, no manual sync needed.
- **Current line highlight** — Editor only. CodePreview is read-only with no insertion point, so no current line highlight there.
- **Gutter background** — `chromeBackground` (blended bg 85%/fg 15%), provides subtle contrast with the editor background.
- **Line number text color** — `chromeTextSecondary` (foreground @ 50% alpha), per ticket spec.
- **Separator line** — `chromeBorder` (foreground @ 20% alpha), thin vertical line between gutter and code.
- **Click behavior** — clicking a line number selects the entire line.
- **Font** — `FontManager.shared.activeFont` at ~0.85x size (~11pt at default 13pt).

## Tasks

- [x] 🟩 **Step 1: Create LineNumberGutterView (NSRulerView subclass)**
  - [x] 🟩 Create `totalcommander/UI/Preview/LineNumberGutterView.swift`
  - [x] 🟩 Subclass `NSRulerView`, override `requiredThickness` to auto-size based on digit count
  - [x] 🟩 Override `drawHashMarksAndLabels(in:)` to draw line numbers right-aligned in the gutter
  - [x] 🟩 Draw gutter background fill using `chromeBackground`
  - [x] 🟩 Draw separator line on trailing edge using `chromeBorder`
  - [x] 🟩 Draw line number text using `chromeTextSecondary` and scaled font
  - [x] 🟩 Handle click in gutter to select the entire clicked line via `mouseDown(with:)`

- [x] 🟩 **Step 2: Add optional current line highlight support**
  - [x] 🟩 Add a `highlightsCurrentLine: Bool` property (default `false`)
  - [x] 🟩 When enabled, draw a subtle background band across the current insertion point's line
  - [x] 🟩 Observe `NSTextView.selectedRanges` or `NSText.didChangeSelectionNotification` to update on cursor move

- [x] 🟩 **Step 3: Integrate into CodePreviewViewController**
  - [x] 🟩 Enable `scrollView.hasVerticalRuler = true` and `scrollView.rulersVisible = true`
  - [x] 🟩 Create and attach `LineNumberGutterView` as `scrollView.verticalRulerView`
  - [x] 🟩 Refresh gutter on file load (`loadFile`)
  - [x] 🟩 Refresh gutter on theme change and font change (existing observers)

- [x] 🟩 **Step 4: Integrate into EditorViewController**
  - [x] 🟩 Enable `scrollView.hasVerticalRuler = true` and `scrollView.rulersVisible = true`
  - [x] 🟩 Create and attach `LineNumberGutterView` as `scrollView.verticalRulerView`
  - [x] 🟩 Set `highlightsCurrentLine = true`
  - [x] 🟩 Refresh gutter on file load, theme change, font change, and text edits

- [x] 🟩 **Step 5: Add to Xcode project**
  - [x] 🟩 Add `LineNumberGutterView.swift` to the Xcode project target

- [x] 🟩 **Step 6: Verify**
  - [x] 🟩 Build succeeds with no warnings
  - [x] 🟩 Line numbers visible in code preview and editor for sample files
  - [x] 🟩 Gutter auto-sizes for files with varying line counts
  - [x] 🟩 Theme and font changes update gutter immediately
  - [x] 🟩 Click on line number selects the full line
  - [x] 🟩 Current line highlighted in editor only
