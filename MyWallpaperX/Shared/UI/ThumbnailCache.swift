//
//  ThumbnailCache.swift
//  MyWallpaperX
//
//  三模块共用的异步缩略图加载缓存。
//  合并相同路径的并发请求（in-flight deduplication），
//  后台解码，主线程回调，NSCache 内存缓存 + 磁盘持久化缓存。
//

import AppKit
import CryptoKit

/// 异步缩略图加载缓存。
/// 线程安全：并发读写通过 NSLock 保护 in-flight 表，NSCache 本身线程安全。
final class ThumbnailCache {

    /// 缓存容量（最大图片数量）
    private let countLimit: Int

    private let decodeQueue: DispatchQueue
    private let imageCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()

    /// 磁盘缓存目录
    private static let diskCacheDir: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX")
            .appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    /// - Parameters:
    ///   - label: decode queue 标识，建议用模块前缀区分
    ///   - countLimit: 内存缓存最大图片数，默认 360
    init(label: String = "com.mywallpaper.thumbnail.decode",
         countLimit: Int = 360) {
        self.countLimit = countLimit
        self.decodeQueue = DispatchQueue(label: label, qos: .utility)
        imageCache.countLimit = countLimit
    }

    // MARK: - 公开接口

    /// 加载缩略图。内存缓存命中则同步回调，磁盘缓存命中则异步快速读取，否则后台解码。
    func load(
        forKey key: String,
        loader: @escaping () -> NSImage?,
        completion: @escaping (NSImage?) -> Void
    ) {
        let cacheKey = key as NSString
        // 1. 内存缓存
        if let cached = imageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        lock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[key] = [completion]
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            // 2. 磁盘缓存
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: cacheKey)
                self.finish(key: key, image: image)
                return
            }
            // 3. 解码原图
            let image = loader()
            if let image {
                self.imageCache.setObject(image, forKey: cacheKey)
                // 写入磁盘缓存（JPEG，压缩质量 0.85）
                Self.writeToDisk(image: image, url: diskURL)
            }
            self.finish(key: key, image: image)
        }
    }

    /// 预取：触发后台加载但不注册回调。
    func prefetch(forKey key: String, loader: @escaping () -> NSImage?) {
        let cacheKey = key as NSString
        guard imageCache.object(forKey: cacheKey) == nil else { return }

        lock.lock()
        guard inFlight[key] == nil else { lock.unlock(); return }
        inFlight[key] = []
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: cacheKey)
                self.finish(key: key, image: image)
                return
            }
            let image = loader()
            if let image {
                self.imageCache.setObject(image, forKey: cacheKey)
                Self.writeToDisk(image: image, url: diskURL)
            }
            self.finish(key: key, image: image)
        }
    }

    /// 清空内存缓存（磁盘缓存保留）
    func removeAll() {
        imageCache.removeAllObjects()
    }

    /// 清空磁盘缓存
    static func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 内部

    private func finish(key: String, image: NSImage?) {
        lock.lock()
        let completions = inFlight.removeValue(forKey: key) ?? []
        lock.unlock()
        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private static func diskCacheURL(for key: String) -> URL {
        // 用 SHA256 哈希作为文件名，避免路径中的特殊字符
        let hash = SHA256.hash(data: Data(key.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    private static func writeToDisk(image: NSImage, url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? jpegData.write(to: url, options: .atomic)
    }
}
