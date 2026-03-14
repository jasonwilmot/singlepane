// ThumbnailService.swift
// Actor-isolated thumbnail generation using QuickLook Thumbnailing framework.
// Generates thumbnails lazily for visible cells with in-memory caching.
// Falls back to NSWorkspace file-type icons for non-previewable files.

import AppKit
import QuickLookThumbnailing

actor ThumbnailService {

    /// Shared singleton for app-wide thumbnail generation.
    static let shared = ThumbnailService()

    /// In-memory cache keyed by "filePath_size" string.
    /// Evicts automatically under memory pressure.
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    /// QuickLook thumbnail generator instance.
    private let generator = QLThumbnailGenerator.shared

    // MARK: - Public API

    /// Returns a cached thumbnail or generates one asynchronously.
    /// Falls back to the file-type icon if QuickLook cannot produce a thumbnail.
    func thumbnail(for url: URL, size: ThumbnailSize) async -> NSImage {
        let key = cacheKey(url: url, size: size)

        // Cache hit — return immediately
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Generate via QuickLook
        let pointSize = size.pointSize
        let cgSize = CGSize(width: pointSize, height: pointSize)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: cgSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await generator.generateBestRepresentation(for: request)
            let image = representation.nsImage
            cache.setObject(image, forKey: key)
            return image
        } catch {
            // QuickLook failed — fall back to file-type icon
            let icon = await MainActor.run {
                NSWorkspace.shared.icon(forFile: url.path)
            }
            cache.setObject(icon, forKey: key)
            return icon
        }
    }

    /// Clears the entire thumbnail cache (e.g. on memory warning).
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Helpers

    /// Builds a cache key combining file path and size tier.
    private func cacheKey(url: URL, size: ThumbnailSize) -> NSString {
        "\(url.path)_\(size.rawValue)" as NSString
    }
}
