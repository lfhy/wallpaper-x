import Foundation
import AppKit
import AVFoundation
import CryptoKit

final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()

    private let workQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.download-thumbnail",
        qos: .utility
    )
    private let generationLimiter = DispatchSemaphore(value: 2)
    private let lock = NSLock()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]

    private init() {}

    func cachedThumbnail(for videoURL: URL) -> NSImage? {
        let outputURL = thumbnailOutputURL(for: videoURL)
        guard let image = NSImage(contentsOf: outputURL),
              !steamWorkshopPreviewImageLooksSuspicious(image) else {
            return nil
        }
        return image
    }

    func generateThumbnail(for videoURL: URL, completion: @escaping (NSImage?) -> Void) {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        if let cached = cachedThumbnail(for: videoURL) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        let key = cacheKey(for: videoURL)
        lock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[key] = [completion]
        lock.unlock()

        workQueue.async {
            self.generationLimiter.wait()
            defer { self.generationLimiter.signal() }

            let image = self.createThumbnail(for: videoURL)
            if let image {
                self.persistThumbnail(image, for: videoURL)
            }
            self.finish(key: key, image: image)
        }
    }

    private func finish(key: String, image: NSImage?) {
        lock.lock()
        let completions = inFlight.removeValue(forKey: key) ?? []
        lock.unlock()

        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private func createThumbnail(for videoURL: URL) -> NSImage? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 960, height: 960)

        let candidateTimes = [
            CMTime(seconds: 1, preferredTimescale: 600),
            CMTime(seconds: 0.25, preferredTimescale: 600),
            CMTime.zero
        ]

        for time in candidateTimes {
            guard let cgImage = generateCGImage(using: imageGenerator, at: time) else { continue }
            let image = NSImage(cgImage: cgImage, size: .zero)
            if !steamWorkshopPreviewImageLooksSuspicious(image) {
                return image
            }
        }
        return nil
    }

    private func generateCGImage(
        using generator: AVAssetImageGenerator,
        at time: CMTime
    ) -> CGImage? {
        var result: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
            result = cgImage
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private func persistThumbnail(_ image: NSImage, for videoURL: URL) {
        let outputURL = thumbnailOutputURL(for: videoURL)
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
        try? data.write(to: outputURL, options: [.atomic])
    }

    private func thumbnailOutputURL(for videoURL: URL) -> URL {
        Self.cacheRootURL
            .appendingPathComponent(cacheKey(for: videoURL))
            .appendingPathExtension("jpg")
    }

    private func cacheKey(for videoURL: URL) -> String {
        let normalizedPath = videoURL.standardizedFileURL.path
        let values = try? videoURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationStamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let rawKey = "\(normalizedPath)|\(modificationStamp)|\(fileSize)"
        return SHA256.hash(data: Data(rawKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let cacheRootURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("GeneratedDownloadThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
