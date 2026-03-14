# 005: JSON/YAML Collapsible Tree View

**Priority:** P1
**Effort:** Medium
**Labels:** Feature, Preview
**Phase:** 1 — Must-Have

## Problem

We pretty-print JSON in the code preview but offer no structural navigation. Competitors like OK JSON and Dadroit provide collapsible tree views with key path navigation. For a file manager, structured data browsing is a key differentiator — users open JSON/YAML configs constantly and need to navigate deep nesting efficiently.

## Requirements

### Tree View
- Collapsible/expandable nodes for objects and arrays
- Display key names, value types, and preview of values
- Array items show index (`[0]`, `[1]`, etc.)
- Object nodes show child count when collapsed (e.g., `config: {12 keys}`)
- Array nodes show item count when collapsed (e.g., `items: [42 items]`)
- Color-code value types: strings (green), numbers (cyan), booleans (magenta), null (muted)

### Navigation
- Key path breadcrumb at top showing current position (e.g., `root > config > database > pool`)
- Click any breadcrumb segment to jump to that level
- Copy key path on right-click (e.g., `config.database.pool.maxSize`)
- Copy value on right-click

### Search
- Filter/search within the tree (highlight matching keys/values)
- Cmd+F to find in structure

### Mode Toggle
- Toggle between tree view and formatted text view (current pretty-print)
- Default to tree view for JSON/YAML, text view for everything else

### YAML Support
- Parse YAML into the same tree structure
- Handle YAML-specific types (anchors, aliases, multi-line strings)

## Implementation Notes

- Use `NSOutlineView` for the tree — native AppKit, supports expand/collapse, keyboard navigation
- Parse JSON via `JSONSerialization` (already used for pretty-print)
- Parse YAML via a Swift YAML library (Yams) or built-in if available
- Tree data model: recursive enum `JSONNode { case object([(String, JSONNode)]), array([JSONNode]), string(String), number(NSNumber), bool(Bool), null }`
- This should be a new view controller that `PreviewContainerViewController` routes to for JSON/YAML files

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — add routing for JSON/YAML to tree view
- New: `totalcommander/UI/Preview/StructuredDataViewController.swift`
- New: `totalcommander/Models/JSONTreeNode.swift`

## Acceptance Criteria

- [ ] JSON files open in collapsible tree view by default
- [ ] YAML files open in collapsible tree view by default
- [ ] Nodes expand/collapse with click or arrow keys
- [ ] Key path breadcrumb updates as user navigates
- [ ] Right-click copy key path works
- [ ] Right-click copy value works
- [ ] Toggle to formatted text view and back
- [ ] Search/filter within tree
- [ ] Files > 10MB display within 1 second (streaming parse)
- [ ] Theme-aware colors for all value types
