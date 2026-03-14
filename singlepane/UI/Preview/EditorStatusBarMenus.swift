// EditorStatusBarMenus.swift
// Builds NSMenu instances for the status bar's clickable items:
//   • Encoding menu: "Reopen with Encoding" + "Save with Encoding" sections
//   • Line ending menu: LF, CRLF, CR with checkmark on current
//   • Indent menu: "Indent Using" + "Convert Indentation" sections
//
// Each menu uses tag-based item identification and a single target/action pair
// per section. The PreviewContainerViewController acts as the menu target
// and routes actions to EditorViewController.

import AppKit

/// Builds menus for the editor status bar.
/// Stateless — all methods are static and return configured NSMenu instances.
enum EditorStatusBarMenus {

    // MARK: - Encoding Menu

    /// Builds the encoding menu with "Reopen with Encoding" and "Save with Encoding" sections.
    /// The current encoding gets a checkmark in both sections.
    static func encodingMenu(
        current: String.Encoding,
        reopenTarget: AnyObject,
        reopenAction: Selector,
        saveTarget: AnyObject,
        saveAction: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        // Section: Reopen with Encoding
        let reopenHeader = NSMenuItem(title: "Reopen with Encoding", action: nil, keyEquivalent: "")
        reopenHeader.isEnabled = false
        menu.addItem(reopenHeader)

        for entry in EncodingInfo.commonEncodings {
            let item = NSMenuItem(title: entry.name, action: reopenAction, keyEquivalent: "")
            item.target = reopenTarget
            item.tag = Int(entry.encoding.rawValue)
            item.state = entry.encoding == current ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Section: Save with Encoding
        let saveHeader = NSMenuItem(title: "Save with Encoding", action: nil, keyEquivalent: "")
        saveHeader.isEnabled = false
        menu.addItem(saveHeader)

        for entry in EncodingInfo.commonEncodings {
            let item = NSMenuItem(title: entry.name, action: saveAction, keyEquivalent: "")
            item.target = saveTarget
            item.tag = Int(entry.encoding.rawValue)
            item.state = entry.encoding == current ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    // MARK: - Line Ending Menu

    /// Builds the line ending menu with LF, CRLF, CR options.
    /// The current line ending gets a checkmark.
    static func lineEndingMenu(
        current: LineEnding,
        target: AnyObject,
        action: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        let options: [(title: String, ending: LineEnding)] = [
            ("LF (Unix/macOS)", .lf),
            ("CRLF (Windows)", .crlf),
            ("CR (Classic Mac)", .cr),
        ]

        for option in options {
            let item = NSMenuItem(title: option.title, action: action, keyEquivalent: "")
            item.target = target
            item.tag = lineEndingTag(option.ending)
            item.state = option.ending == current ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    /// Encodes a LineEnding as an integer tag for menu item identification.
    static func lineEndingTag(_ ending: LineEnding) -> Int {
        switch ending {
        case .lf:    0
        case .crlf:  1
        case .cr:    2
        case .mixed: 3
        }
    }

    /// Decodes a menu item tag back to a LineEnding.
    static func lineEnding(fromTag tag: Int) -> LineEnding {
        switch tag {
        case 0:  .lf
        case 1:  .crlf
        case 2:  .cr
        default: .lf
        }
    }

    // MARK: - Indent Menu

    /// Builds the indent style menu with "Indent Using" and "Convert Indentation" sections.
    /// The current style gets a checkmark in the "Indent Using" section.
    static func indentMenu(
        current: IndentStyle,
        indentTarget: AnyObject,
        indentAction: Selector,
        convertTarget: AnyObject,
        convertAction: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        // Section: Indent Using
        let indentHeader = NSMenuItem(title: "Indent Using", action: nil, keyEquivalent: "")
        indentHeader.isEnabled = false
        menu.addItem(indentHeader)

        let spaceOptions = [2, 4, 8]
        for count in spaceOptions {
            let style = IndentStyle.spaces(count)
            let item = NSMenuItem(
                title: "\(count) Spaces", action: indentAction, keyEquivalent: ""
            )
            item.target = indentTarget
            item.tag = count // positive = spaces(count)
            item.state = current == style ? .on : .off
            menu.addItem(item)
        }

        let tabItem = NSMenuItem(title: "Tabs", action: indentAction, keyEquivalent: "")
        tabItem.target = indentTarget
        tabItem.tag = -1 // negative = tabs
        tabItem.state = current == .tabs ? .on : .off
        menu.addItem(tabItem)

        menu.addItem(.separator())

        // Section: Convert Indentation
        let convertHeader = NSMenuItem(title: "Convert Indentation", action: nil, keyEquivalent: "")
        convertHeader.isEnabled = false
        menu.addItem(convertHeader)

        for count in spaceOptions {
            let item = NSMenuItem(
                title: "Convert to \(count) Spaces", action: convertAction, keyEquivalent: ""
            )
            item.target = convertTarget
            item.tag = count
            menu.addItem(item)
        }

        let convertTabItem = NSMenuItem(
            title: "Convert to Tabs", action: convertAction, keyEquivalent: ""
        )
        convertTabItem.target = convertTarget
        convertTabItem.tag = -1
        menu.addItem(convertTabItem)

        return menu
    }

    /// Decodes a menu item tag to an IndentStyle.
    /// Positive tags = spaces(tag), negative = tabs.
    static func indentStyle(fromTag tag: Int) -> IndentStyle {
        tag < 0 ? .tabs : .spaces(tag)
    }
}
