// ColumnIdentifiers.swift
// Shared column identifiers for NSTableView file list columns.

import AppKit

extension NSUserInterfaceItemIdentifier {
    static let fileName = NSUserInterfaceItemIdentifier("FileName")
    static let fileSize = NSUserInterfaceItemIdentifier("FileSize")
    static let fileDateModified = NSUserInterfaceItemIdentifier("FileDateModified")
    static let fileKind = NSUserInterfaceItemIdentifier("FileKind")
    static let fileCopyPath = NSUserInterfaceItemIdentifier("FileCopyPath")
    static let filePasteToTerminal = NSUserInterfaceItemIdentifier("FilePasteToTerminal")
    static let searchFileName = NSUserInterfaceItemIdentifier("SearchFileName")
    static let searchExcerpt = NSUserInterfaceItemIdentifier("SearchExcerpt")
}
