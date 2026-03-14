// ThumbnailService.swift
// Actor-isolated thumbnail generation using QuickLook Thumbnailing framework.
// Generates thumbnails lazily for visible cells with in-memory caching.
// Falls back to NSWorkspace file-type icons for non-previewable files.

import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

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

    /// Image UTTypes eligible for QuickLook thumbnail generation.
    private static let imageTypes: Set<String> = [
        "public.image", "public.jpeg", "public.png", "public.tiff",
        "public.heic", "public.heif", "public.svg-image",
        "com.compuserve.gif", "public.webp", "com.microsoft.bmp",
        "com.microsoft.ico", "public.icns", "public.camera-raw-image"
    ]

    /// Returns a cached thumbnail or generates one asynchronously.
    /// Only generates QuickLook thumbnails for image files.
    /// Non-image files receive their file-type icon directly.
    func thumbnail(for url: URL, size: ThumbnailSize) async -> NSImage {
        let key = cacheKey(url: url, size: size)

        // Cache hit — return immediately
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Only generate thumbnails for image files
        if !Self.isImageFile(url) {
            let icon = await MainActor.run {
                NSWorkspace.shared.icon(forFile: url.path)
            }
            cache.setObject(icon, forKey: key)
            return icon
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

    /// Checks whether the file at `url` is an image type eligible for thumbnail generation.
    private static func isImageFile(_ url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
              let uti = resourceValues.typeIdentifier else {
            return false
        }
        if imageTypes.contains(uti) { return true }
        // Also check UTType conformance for subtypes (e.g. vendor-specific image formats)
        if #available(macOS 11.0, *) {
            if let utType = UTType(uti) {
                return utType.conforms(to: .image)
            }
        }
        return false
    }
}
