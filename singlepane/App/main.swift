// main.swift
// Explicit NSApplication setup — no @main attribute.
// Sets activation policy to .regular so the app appears in the Dock.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
