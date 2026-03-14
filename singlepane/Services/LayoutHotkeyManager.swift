// LayoutHotkeyManager.swift
// Singleton that manages keyboard hotkey bindings for layout presets.
// Persists to UserDefaults via JSONEncoder/JSONDecoder.
// Mirrors the CustomLayoutManager/ThemeManager pattern.

import AppKit

// MARK: - HotkeyBinding

/// A keyboard shortcut binding: key code + modifier flags.
/// Codable for UserDefaults persistence.
struct HotkeyBinding: Codable, Equatable, Sendable {

    /// The hardware-independent virtual key code (NSEvent.keyCode).
    let keyCode: UInt16

    /// Raw value of NSEvent.ModifierFlags for Codable conformance.
    /// Stores only the device-independent flags (Cmd, Ctrl, Option, Shift).
    let modifierFlagsRawValue: UInt

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
    }

    /// Reconstructed modifier flags from the stored raw value.
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    /// Whether this binding matches a given key event.
    func matches(event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifierFlags
    }

    /// Human-readable string representation (e.g., "⌘1", "⌃⌥A").
    var displayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option)  { parts.append("⌥") }
        if modifierFlags.contains(.shift)   { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }

        let keyName = Self.keyCodeToString(keyCode)
        parts.append(keyName)
        return parts.joined()
    }

    /// Maps a virtual key code to a human-readable key name.
    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Number row
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        // Letters
        case 0:  return "A"
        case 11: return "B"
        case 8:  return "C"
        case 2:  return "D"
        case 14: return "E"
        case 3:  return "F"
        case 5:  return "G"
        case 4:  return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1:  return "S"
        case 17: return "T"
        case 32: return "U"
        case 9:  return "V"
        case 13: return "W"
        case 7:  return "X"
        case 16: return "Y"
        case 6:  return "Z"
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Special keys
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        default:
            return "Key\(keyCode)"
        }
    }
}

// MARK: - LayoutHotkeyManager

@MainActor
@Observable
final class LayoutHotkeyManager {

    // MARK: - Singleton

    static let shared = LayoutHotkeyManager()

    // MARK: - State

    /// Layout identifier → hotkey binding. Key is SnapLayout.rawValue or CustomLayout UUID string.
    private(set) var bindings: [String: HotkeyBinding] = [:]

    // MARK: - UserDefaults Key

    private static let storageKey = "layoutHotkeyBindings"

    // MARK: - Init

    private init() {
        load()
        purgeOrphanedBindings()
    }

    // MARK: - Query

    /// Returns the hotkey binding for a layout identifier, if any.
    func hotkey(for layoutID: String) -> HotkeyBinding? {
        bindings[layoutID]
    }

    /// Whether a layout has a hotkey assigned.
    func hasHotkey(for layoutID: String) -> Bool {
        bindings[layoutID] != nil
    }

    /// Returns the layout identifier that already uses this key combo, if any.
    func existingBinding(for binding: HotkeyBinding) -> String? {
        bindings.first(where: { $0.value == binding })?.key
    }

    /// Finds the layout identifier matching a key event, if any.
    func layoutIdentifier(for event: NSEvent) -> String? {
        bindings.first(where: { $0.value.matches(event: event) })?.key
    }

    // MARK: - Mutate

    /// Assigns a hotkey to a layout. Overwrites any previous binding for this layout.
    func setHotkey(for layoutID: String, binding: HotkeyBinding) {
        bindings[layoutID] = binding
        persist()
    }

    /// Removes the hotkey for a layout.
    func removeHotkey(for layoutID: String) {
        bindings.removeValue(forKey: layoutID)
        persist()
    }

    // MARK: - Validation

    /// Result of validating a proposed hotkey binding.
    enum ValidationResult {
        case valid
        case dangerous(reason: String)
        case conflict(existingLayoutID: String)
    }

    /// Validates whether a binding can be assigned to a layout.
    func validate(binding: HotkeyBinding, for layoutID: String) -> ValidationResult {
        if isDangerous(binding) {
            return .dangerous(reason: "This shortcut is reserved by the system.")
        }
        if let existing = existingBinding(for: binding), existing != layoutID {
            return .conflict(existingLayoutID: existing)
        }
        return .valid
    }

    /// Checks if a binding conflicts with essential macOS shortcuts.
    private func isDangerous(_ binding: HotkeyBinding) -> Bool {
        let mods = binding.modifierFlags
        let key = binding.keyCode

        // Must have at least one modifier
        let hasModifier = mods.contains(.command) || mods.contains(.control) || mods.contains(.option)
        if !hasModifier { return true }

        // Cmd-only dangerous shortcuts
        if mods == .command {
            switch key {
            case 12: return true  // Cmd+Q
            case 13: return true  // Cmd+W
            case 4:  return true  // Cmd+H
            case 46: return true  // Cmd+M
            case 0:  return true  // Cmd+A
            case 8:  return true  // Cmd+C
            case 9:  return true  // Cmd+V
            case 7:  return true  // Cmd+X
            case 6:  return true  // Cmd+Z
            case 1:  return true  // Cmd+S
            case 45: return true  // Cmd+N
            case 48: return true  // Cmd+Tab
            default: break
            }
        }

        return false
    }

    // MARK: - Display Name Lookup

    /// Returns a human-readable name for a layout identifier.
    /// Used in conflict messages (e.g., "Already assigned to 'All Panels'").
    func displayName(for layoutID: String) -> String {
        // Check preset layouts first
        if let preset = SnapLayout(rawValue: layoutID) {
            return preset.displayName
        }
        // Check custom layouts by UUID
        if let uuid = UUID(uuidString: layoutID),
           let index = CustomLayoutManager.shared.customLayouts.firstIndex(where: { $0.id == uuid }) {
            return "Custom \(index + 1)"
        }
        return layoutID
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else {
            return
        }
        bindings = decoded
    }

    private func persist() {
        if bindings.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        } else {
            guard let data = try? JSONEncoder().encode(bindings) else { return }
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        UserDefaults.standard.synchronize()
    }

    /// Removes hotkey bindings for layouts that no longer exist.
    /// Runs on init to clean up orphans left by deleted custom layouts.
    private func purgeOrphanedBindings() {
        let customIDs = Set(CustomLayoutManager.shared.customLayouts.map(\.id.uuidString))
        let presetIDs = Set(SnapLayout.allCases.map(\.rawValue))
        let validIDs = customIDs.union(presetIDs)

        let orphans = bindings.keys.filter { !validIDs.contains($0) }
        guard !orphans.isEmpty else { return }

        for key in orphans {
            bindings.removeValue(forKey: key)
        }
        persist()
    }
}
