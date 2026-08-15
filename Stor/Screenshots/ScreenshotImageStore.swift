import AppKit
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Content-addressed storage for screenshot layer images.
///
/// Layers used to embed image bytes directly in the template's layer JSON, which meant
/// every property edit re-encoded megabytes of PNG data. Layers now hold a short digest
/// and the bytes live on disk, so editing a layer only rewrites a few hundred bytes.
///
/// Files are named by the SHA-256 of their contents, so importing the same screenshot
/// into several layers or templates stores it once.
@MainActor
final class ScreenshotImageStore {
    static let shared = ScreenshotImageStore()

    private let directory: URL
    private var dataCache: [String: Data] = [:]
    private var imageCache: [String: NSImage] = [:]
    private var previewCache: [String: NSImage] = [:]

    /// Longest edge of the downsampled canvas-preview image. The editor canvas is only a
    /// few hundred points wide, so drawing the full-resolution screenshot every frame
    /// wastes GPU/CPU; export still uses `image(for:)`.
    private static let previewMaxPixelSize = 1200

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL.temporaryDirectory
            self.directory = base
                .appendingPathComponent("AscendKit", isDirectory: true)
                .appendingPathComponent("ScreenshotImages", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: - Writing

    /// Writes `data` if it is not already stored and returns its reference.
    @discardableResult
    func store(_ data: Data) -> String {
        let ref = Self.reference(for: data)
        let url = fileURL(for: ref)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        dataCache[ref] = data
        return ref
    }

    static func reference(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Reading

    func data(for ref: String) -> Data? {
        if let cached = dataCache[ref] { return cached }
        guard let data = try? Data(contentsOf: fileURL(for: ref)) else { return nil }
        dataCache[ref] = data
        return data
    }

    /// Full-resolution image, used by the PNG export path.
    func image(for ref: String) -> NSImage? {
        if let cached = imageCache[ref] { return cached }
        guard let data = data(for: ref), let image = NSImage(data: data) else { return nil }
        imageCache[ref] = image
        return image
    }

    /// Downsampled image for the on-canvas preview. Falls back to the full image.
    func previewImage(for ref: String) -> NSImage? {
        if let cached = previewCache[ref] { return cached }
        guard let data = data(for: ref) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.previewMaxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image(for: ref)
        }
        let thumbnail = NSImage(cgImage: cg, size: .zero)
        previewCache[ref] = thumbnail
        return thumbnail
    }

    // MARK: - Housekeeping

    /// Deletes stored images no layer references any more. Safe to call with the refs of
    /// every template in the store; anything missing from `keeping` is unreachable.
    func pruneUnreferenced(keeping refs: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where !refs.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            dataCache.removeValue(forKey: file.lastPathComponent)
            imageCache.removeValue(forKey: file.lastPathComponent)
            previewCache.removeValue(forKey: file.lastPathComponent)
        }
    }

    private func fileURL(for ref: String) -> URL {
        directory.appendingPathComponent(ref, isDirectory: false)
    }
}

extension ScreenshotImageStore {
    /// Every image reference held by any template, across all apps. Anything not in this
    /// set is unreachable and safe to delete.
    static func referencedImages(in context: ModelContext) -> Set<String> {
        let templates = (try? context.fetch(FetchDescriptor<ScreenshotTemplate>())) ?? []
        return Set(templates.flatMap { $0.layers.compactMap(\.imageRef) })
    }
}
