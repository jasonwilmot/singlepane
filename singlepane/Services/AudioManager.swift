// AudioManager.swift
// Manages in-app audio playback for hook events.
// Plays random audio clips from the active voice pack when events arrive.
// Queued: only one clip plays at a time; subsequent requests wait in line.

import AVFoundation

@MainActor
@Observable
final class AudioManager {

    // MARK: - Singleton

    static let shared = AudioManager()

    // MARK: - State

    /// The currently selected voice pack directory name.
    private(set) var selectedVoicePack: String

    /// Whether audio playback is muted.
    var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.mutedKey) }
    }

    /// All discovered voice packs (bundled + custom from Application Support).
    private(set) var availableVoicePacks: [VoicePack]

    // MARK: - Playback

    /// The currently playing handle (only one at a time).
    private var currentHandle: AudioPlayerHandle?

    /// Queued URLs waiting to play after the current clip finishes.
    private var pendingQueue: [URL] = []

    /// Tracks the last played file per event to avoid back-to-back repeats.
    private var lastPlayed: [String: URL] = [:]

    // MARK: - UserDefaults Keys

    private static let voicePackKey = "selectedVoicePack"
    private static let mutedKey = "audioMuted"
    private static let mutedHooksKey = "mutedHooksPerPack"
    private static let globalMutedHooksKey = "globalMutedHooks"
    private static let defaultVoicePack = "sunny-singh"

    // MARK: - Init

    private init() {
        // Initialize all stored properties before accessing self
        self.isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)

        // Discover available voice packs from the bundle and custom directory
        let packs = Self.discoverVoicePacks()
        self.availableVoicePacks = packs

        // Restore persisted voice pack selection
        let savedPack = UserDefaults.standard.string(forKey: Self.voicePackKey)
            ?? Self.defaultVoicePack
        self.selectedVoicePack = packs.contains(where: { $0.directoryName == savedPack })
            ? savedPack
            : (packs.first?.directoryName ?? Self.defaultVoicePack)
    }

    // MARK: - Voice Pack Selection

    /// Switch to a voice pack by directory name. Persists the selection.
    /// Accepts any known pack (bundled or custom).
    func selectVoicePack(named name: String) {
        guard availableVoicePacks.contains(where: { $0.directoryName == name }) else { return }
        selectedVoicePack = name
        UserDefaults.standard.set(name, forKey: Self.voicePackKey)

        // Flush any queued clips from the previous pack (don't stop current
        // playback — the preview may still be playing from onPreview).
        pendingQueue.removeAll()
        lastPlayed.removeAll()
    }

    // MARK: - Global Hook Muting

    /// Returns the set of globally muted hook events (applied to all packs).
    func globalMutedHooks() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: Self.globalMutedHooksKey) ?? []
        return Set(array)
    }

    /// Sets whether a specific hook event is globally muted.
    func setGlobalHookMuted(_ muted: Bool, event: String) {
        var hooks = globalMutedHooks()
        if muted {
            hooks.insert(event)
        } else {
            hooks.remove(event)
        }
        UserDefaults.standard.set(Array(hooks), forKey: Self.globalMutedHooksKey)
    }

    /// Returns whether a specific hook event is globally muted.
    func isHookMuted(event: String) -> Bool {
        globalMutedHooks().contains(event)
    }

    // MARK: - Playback

    /// Plays a random audio clip for the given hook event.
    /// Event names map directly to subdirectory names (e.g., "prompt" → prompt/).
    /// If a clip is already playing, the new clip is queued.
    func playSound(event: String) {
        guard !isMuted else { return }
        guard !isHookMuted(event: event) else { return }

        guard let folderURL = resolveEventFolder(event: event, packName: selectedVoicePack) else { return }

        // Collect all audio files in the event folder
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ).filter({ VoicePack.audioExtensions.contains($0.pathExtension.lowercased()) }),
              !files.isEmpty else { return }

        // Pick a random file, avoiding back-to-back repeat
        let candidate: URL
        if files.count > 1, let last = lastPlayed[event] {
            let filtered = files.filter { $0 != last }
            candidate = filtered.randomElement() ?? files.randomElement()!
        } else {
            candidate = files.randomElement()!
        }
        lastPlayed[event] = candidate

        enqueueAndPlay(candidate)
    }

    // MARK: - Preview

    /// Plays a preview clip from the given voice/sound pack.
    /// Tries prompt_17.mp3 first (voice packs), then falls back to the first audio file
    /// in the prompt directory (sound packs use different naming).
    func previewVoice(directoryName: String) {
        guard let promptDir = resolveEventFolder(event: "prompt", packName: directoryName) else { return }

        // Try the canonical preview file first, then fall back to the first audio file
        let canonical = promptDir.appendingPathComponent("prompt_17.mp3")
        let fileURL: URL
        if FileManager.default.fileExists(atPath: canonical.path) {
            fileURL = canonical
        } else if let files = try? FileManager.default.contentsOfDirectory(
            at: promptDir, includingPropertiesForKeys: nil
        ).filter({ VoicePack.audioExtensions.contains($0.pathExtension.lowercased()) }),
                  let first = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
            fileURL = first
        } else {
            return
        }

        stopAll()
        startPlaying(fileURL)
    }

    // MARK: - Queue Management

    /// Stops all current and queued playback immediately.
    private func stopAll() {
        pendingQueue.removeAll()
        currentHandle?.player.stop()
        currentHandle = nil
    }

    /// Adds a URL to the playback queue. If nothing is playing, starts immediately.
    private func enqueueAndPlay(_ url: URL) {
        if currentHandle != nil {
            pendingQueue.append(url)
        } else {
            startPlaying(url)
        }
    }

    /// Starts playback of a single URL.
    private func startPlaying(_ url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let handle = AudioPlayerHandle(player: player)
            currentHandle = handle
            handle.onFinish = { [weak self] in
                self?.playbackDidFinish()
            }
            player.delegate = handle
            player.play()
        } catch {
            // Audio playback is non-critical — play next in queue if any
            playbackDidFinish()
        }
    }

    /// Called when the current clip finishes. Dequeues the next clip if available.
    private func playbackDidFinish() {
        currentHandle = nil
        if !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            startPlaying(next)
        }
    }

    // MARK: - Path Resolution

    /// Resolves the folder URL for a given event within a voice pack.
    /// Checks custom packs first (Application Support), then falls back to the bundle.
    private func resolveEventFolder(event: String, packName: String) -> URL? {
        // Check custom pack directory first
        let customDir = Self.customPacksDirectoryURL
            .appendingPathComponent(packName)
            .appendingPathComponent(event)
        if FileManager.default.fileExists(atPath: customDir.path) {
            return customDir
        }

        // Fall back to bundled pack in Resources/Voices/
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let bundledDir = resourceURL
            .appendingPathComponent("Voices")
            .appendingPathComponent(packName)
            .appendingPathComponent(event)
        if FileManager.default.fileExists(atPath: bundledDir.path) {
            return bundledDir
        }
        return nil
    }

    // MARK: - Custom Pack Storage

    /// Root directory for user-created custom voice packs.
    static let customPacksDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Velocity")
            .appendingPathComponent("CustomVoicePacks")
    }()

    /// Ensures the custom packs root directory exists.
    private static func ensureCustomPacksDirectory() {
        try? FileManager.default.createDirectory(
            at: customPacksDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Custom Pack CRUD

    /// Creates a new custom pack with the given name and empty event subdirectories.
    /// Returns the created VoicePack, or nil if creation failed.
    @discardableResult
    func createCustomPack(named name: String) -> VoicePack? {
        Self.ensureCustomPacksDirectory()
        let packDir = Self.customPacksDirectoryURL.appendingPathComponent(name)

        // Create the pack directory and all event subdirectories
        do {
            for event in VoicePack.hookEvents {
                try FileManager.default.createDirectory(
                    at: packDir.appendingPathComponent(event),
                    withIntermediateDirectories: true
                )
            }
        } catch {
            return nil
        }

        let pack = VoicePack(directoryName: name, storageURL: packDir)
        refreshVoicePacks()
        return pack
    }

    /// Copies an audio file into a custom pack's event subdirectory.
    /// Returns the destination URL, or nil if the copy failed.
    @discardableResult
    func addFile(to packName: String, event: String, from sourceURL: URL) -> URL? {
        let destDir = Self.customPacksDirectoryURL
            .appendingPathComponent(packName)
            .appendingPathComponent(event)

        // Ensure the event directory exists
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            // If a file with the same name exists, remove it first
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            return nil
        }
    }

    /// Removes a single audio file from a custom pack's event subdirectory.
    func removeFile(_ fileName: String, from packName: String, event: String) {
        let fileURL = Self.customPacksDirectoryURL
            .appendingPathComponent(packName)
            .appendingPathComponent(event)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Deletes an entire custom pack. Falls back to the default pack if it was active.
    func deleteCustomPack(_ packName: String) {
        let packDir = Self.customPacksDirectoryURL.appendingPathComponent(packName)
        try? FileManager.default.removeItem(at: packDir)

        // If the deleted pack was selected, revert to the default
        if selectedVoicePack == packName {
            selectedVoicePack = Self.defaultVoicePack
            UserDefaults.standard.set(Self.defaultVoicePack, forKey: Self.voicePackKey)
        }
        refreshVoicePacks()
    }

    /// Renames a custom pack by moving its directory. Updates selection if it was active.
    func renameCustomPack(_ oldName: String, to newName: String) {
        let oldDir = Self.customPacksDirectoryURL.appendingPathComponent(oldName)
        let newDir = Self.customPacksDirectoryURL.appendingPathComponent(newName)
        guard oldDir != newDir else { return }

        do {
            try FileManager.default.moveItem(at: oldDir, to: newDir)
            if selectedVoicePack == oldName {
                selectedVoicePack = newName
                UserDefaults.standard.set(newName, forKey: Self.voicePackKey)
            }
            refreshVoicePacks()
        } catch {
            // Rename failed — keep existing state
        }
    }

    /// Lists audio files in a custom pack's event subdirectory.
    func filesForEvent(_ event: String, in packName: String) -> [URL] {
        let eventDir = Self.customPacksDirectoryURL
            .appendingPathComponent(packName)
            .appendingPathComponent(event)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: eventDir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { VoicePack.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Voice Pack Discovery

    /// Re-scans both bundled and custom pack directories and updates the available packs list.
    func refreshVoicePacks() {
        availableVoicePacks = Self.discoverVoicePacks()
    }

    /// Scans Resources/Voices/ and the custom packs directory for voice packs.
    private static func discoverVoicePacks() -> [VoicePack] {
        var packs: [VoicePack] = []

        // Discover bundled voice packs from the app bundle
        if let voicesURL = Bundle.main.resourceURL?.appendingPathComponent("Voices"),
           let contents = try? FileManager.default.contentsOfDirectory(
            at: voicesURL,
            includingPropertiesForKeys: [URLResourceKey.isDirectoryKey]
           ) {
            let bundled = contents.compactMap { url -> VoicePack? in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return nil }
                return VoicePack(directoryName: url.lastPathComponent)
            }
            packs.append(contentsOf: bundled)
        }

        // Discover custom voice packs from Application Support
        ensureCustomPacksDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: customPacksDirectoryURL,
            includingPropertiesForKeys: [URLResourceKey.isDirectoryKey]
        ) {
            let custom = contents.compactMap { url -> VoicePack? in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return nil }
                return VoicePack(directoryName: url.lastPathComponent, storageURL: url)
            }
            packs.append(contentsOf: custom)
        }

        // Sort: sound packs first, then bundled voices alphabetically, then custom packs alphabetically
        return packs.sorted { a, b in
            // Sound packs before everything
            if a.isSoundPack != b.isSoundPack { return a.isSoundPack }
            // Bundled before custom
            if a.isCustom != b.isCustom { return !a.isCustom }
            // Alphabetically within each group
            return a.displayName < b.displayName
        }
    }
}

// MARK: - VoicePack

/// A discovered voice or sound pack with its directory name and derived display name.
struct VoicePack: Sendable, Identifiable {

    /// The directory name within Resources/Voices/ or CustomVoicePacks/ (e.g., "sunny-singh").
    let directoryName: String

    /// Whether this is a user-created custom pack (stored in Application Support).
    let isCustom: Bool

    /// Root URL of this pack's directory. Nil for bundled packs (resolved from the bundle at playback).
    let storageURL: URL?

    /// The canonical hook event subdirectory names in display order.
    static let hookEvents = ["hello", "prompt", "agent", "stop", "end", "notification"]

    /// Supported audio file extensions.
    static let audioExtensions: Set<String> = ["mp3", "wav", "m4a"]

    // MARK: - Convenience Initializers

    /// Creates a bundled voice pack (loaded from the app bundle).
    init(directoryName: String) {
        self.directoryName = directoryName
        self.isCustom = false
        self.storageURL = nil
    }

    /// Creates a custom voice pack (loaded from Application Support).
    init(directoryName: String, storageURL: URL) {
        self.directoryName = directoryName
        self.isCustom = true
        self.storageURL = storageURL
    }

    /// Whether this is a sound effects pack rather than a voice pack.
    var isSoundPack: Bool { Self.soundPackNames[directoryName] != nil }

    /// Human-readable display name. Custom packs use their directory name title-cased.
    /// Bundled packs check sound pack and ElevenLabs mappings first.
    var displayName: String {
        if let name = Self.soundPackNames[directoryName] { return name }
        if let name = Self.elevenLabsVoiceNames[directoryName] { return name }
        return directoryName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var id: String { directoryName }

    /// Mapping of sound pack directory names to friendly display names.
    private static let soundPackNames: [String: String] = [
        "totalSounds1": "Sound Pack 1",
        "totalSounds2": "Sound Pack 2",
        "totalSounds3": "Sound Pack 3",
    ]

    /// Mapping of ElevenLabs voice IDs to their friendly names.
    /// Looked up from the ElevenLabs API — cached here to avoid runtime API calls.
    private static let elevenLabsVoiceNames: [String: String] = [
        "wFOtYWBAKv6z33WjceQa": "Kamau - Deep and Warm",
        "WMKg7TxPpPWCryaXE42r": "Cruella - Poison Personified",
        "llNlEi50DSCIEuoOIaH7": "Jamie - Upbeat British Ad Voice",
        "mKoqwDP2laxTdq1gEgU6": "Countdown Casey - Radio DJ",
        "Bj9UqZbhQsanLzgalpEG": "Austin - Deep, Raspy and Authentic",
        "RDSy0QN68yhrjuOgqzQ4": "Dr. Quibble - Nerdy Cartoon Scientist",
        "NXaTw4ifg0LAguvKuIwZ": "Posh Josh",
        "BBfN7Spa3cqLPH1xAS22": "Beezle Wheezelby",
        "CKfuQaJKfvUG2Wtrda3Y": "Lison - Seductive and Soft French Accent",
    ]
}

// MARK: - AudioPlayerHandle

/// Wraps AVAudioPlayer to track active playback and auto-cleanup on finish.
/// Stored in a Set so the player stays alive until the clip ends.
@MainActor
final class AudioPlayerHandle: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {

    let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(player: AVAudioPlayer) {
        self.player = player
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinish?()
        }
    }

    override var hash: Int { ObjectIdentifier(self).hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AudioPlayerHandle else { return false }
        return self === other
    }
}
