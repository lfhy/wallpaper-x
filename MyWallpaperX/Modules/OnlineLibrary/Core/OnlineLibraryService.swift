//
//  OnlineLibraryService.swift
//  MyWallpaperX — Modules/OnlineLibrary/Core
//
//  在线图库数据层：Pixabay API 搜索、分页、分类定义、状态发布。
//  依赖：Foundation、Combine（零 Shared/Models 依赖）
//  切换其他图库服务只需替换 buildURL / fetchPage / 数据映射部分。
//

import Foundation
import Combine

private final class OLDownloadTaskDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var expectedBytes: Int64
    let progressHandler: @MainActor (Double) -> Void
    let completion: (Result<URL, Error>) -> Void
    private var finished = false

    init(
        expectedBytes: Int64,
        progressHandler: @escaping @MainActor (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.expectedBytes = expectedBytes
        self.progressHandler = progressHandler
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard total > 0 else { return }
        let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(total)))
        Task { @MainActor in
            self.progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        finished = true
        do {
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try? FileManager.default.removeItem(at: stableURL)
            try FileManager.default.copyItem(at: location, to: stableURL)
            session.finishTasksAndInvalidate()
            completion(.success(stableURL))
        } catch {
            session.finishTasksAndInvalidate()
            completion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, !finished else { return }
        finished = true
        session.finishTasksAndInvalidate()
        completion(.failure(error))
    }
}

// MARK: - 分类

enum OnlineLibraryCategory: String, CaseIterable, Identifiable {
    case all            = ""
    case nature         = "nature"
    case science        = "science"
    case education      = "education"
    case feelings       = "feelings"
    case health         = "health"
    case people         = "people"
    case religion       = "religion"
    case places         = "places"
    case animals        = "animals"
    case industry       = "industry"
    case computer       = "computer"
    case food           = "food"
    case sports         = "sports"
    case transportation = "transportation"
    case travel         = "travel"
    case buildings      = "buildings"
    case business       = "business"
    case music          = "music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:            return "全部"
        case .nature:         return "自然"
        case .science:        return "科学"
        case .education:      return "教育"
        case .feelings:       return "情感"
        case .health:         return "健康"
        case .people:         return "人物"
        case .religion:       return "宗教"
        case .places:         return "地点"
        case .animals:        return "动物"
        case .industry:       return "工业"
        case .computer:       return "科技"
        case .food:           return "美食"
        case .sports:         return "运动"
        case .transportation: return "交通"
        case .travel:         return "旅行"
        case .buildings:      return "建筑"
        case .business:       return "商业"
        case .music:          return "音乐"
        }
    }
}

// MARK: - 排序

enum OnlineLibraryOrder: String, CaseIterable, Identifiable {
    case popular = "popular"
    case latest  = "latest"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .popular: return "热门"
        case .latest:  return "最新"
        }
    }
}

// MARK: - 搜索参数

/// OL-11：消除魔法数字，统一 perPage 默认值
let kOLDefaultPerPage = 30

struct OnlineLibrarySearchParams: Equatable {
    var query:    String                 = ""
    var category: OnlineLibraryCategory  = .all
    var page:     Int                    = 1
    var perPage:  Int                    = kOLDefaultPerPage
    var order:    OnlineLibraryOrder     = .popular
}

// MARK: - 数据模型

struct OnlineLibraryVideoItem: Identifiable, Equatable {
    let id:           Int
    let pageURL:      String
    let tags:         String
    let duration:     Int
    let user:         String
    let videos:       OnlineLibraryVideoFiles

    var bestVideoURL: URL? {
        if let u = videos.large?.url,  !u.isEmpty { return URL(string: u) }
        if let u = videos.medium?.url, !u.isEmpty { return URL(string: u) }
        if let u = videos.small?.url,  !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.url,   !u.isEmpty { return URL(string: u) }
        return nil
    }

    var previewThumbnailURL: URL? {
        if let u = videos.medium?.thumbnail, !u.isEmpty { return URL(string: u) }
        if let u = videos.small?.thumbnail,  !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.thumbnail,   !u.isEmpty { return URL(string: u) }
        return nil
    }

    /// 悬停预览用视频 URL，优先 small（画质/体积平衡），fallback tiny
    var videoPreviewURL: URL? {
        if let u = videos.small?.url, !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.url,  !u.isEmpty { return URL(string: u) }
        return nil
    }

    var displayTitle: String {
        let parts = tags.split(separator: ",").prefix(3)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
        return parts.isEmpty ? "Pixabay #\(id)" : parts
    }

    var durationString: String {
        let m = duration / 60, s = duration % 60
        if m > 0, s > 0 { return "\(m)m\(s)s" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    var resolutionString: String? {
        let f = videos.large ?? videos.medium ?? videos.small ?? videos.tiny
        guard let f, f.width > 0, f.height > 0 else { return nil }
        return "\(f.width)×\(f.height)"
    }

    var fileSizeString: String? {
        let f = videos.large ?? videos.medium ?? videos.small ?? videos.tiny
        guard let bytes = f?.size, bytes > 0 else { return nil }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1fGB", mb / 1024)
        }
        if mb >= 100 {
            return String(format: "%.0fMB", mb)
        }
        if mb >= 10 {
            return String(format: "%.1fMB", mb)
        }
        return String(format: "%.2fMB", mb)
    }
}

struct OnlineLibraryVideoFiles: Equatable {
    let large:  OnlineLibraryVideoFile?
    let medium: OnlineLibraryVideoFile?
    let small:  OnlineLibraryVideoFile?
    let tiny:   OnlineLibraryVideoFile?
}

struct OnlineLibraryVideoFile: Equatable {
    let url:       String
    let width:     Int
    let height:    Int
    let size:      Int
    let thumbnail: String
}

// MARK: - API 响应解码（私有）

private struct OLResponse: Decodable {
    let totalHits: Int
    let hits:      [OLHit]
}

private struct OLHit: Decodable {
    let id: Int; let pageURL: String; let tags: String
    let duration: Int; let user: String
    let videos: OLHitVideos
    enum CodingKeys: String, CodingKey {
        case id, pageURL, tags, duration, user, videos
    }
}

private struct OLHitVideos: Decodable {
    let large: OLHitFile?; let medium: OLHitFile?
    let small: OLHitFile?; let tiny:   OLHitFile?
}

private struct OLHitFile: Decodable {
    let url: String; let width: Int; let height: Int
    let size: Int;   let thumbnail: String
}

private extension OLHit {
    func toItem() -> OnlineLibraryVideoItem {
        func map(_ f: OLHitFile?) -> OnlineLibraryVideoFile? {
            f.map { OnlineLibraryVideoFile(url: $0.url, width: $0.width,
                                          height: $0.height, size: $0.size,
                                          thumbnail: $0.thumbnail) }
        }
        return OnlineLibraryVideoItem(
            id: id, pageURL: pageURL, tags: tags, duration: duration, user: user,
            videos: OnlineLibraryVideoFiles(
                large: map(videos.large), medium: map(videos.medium),
                small: map(videos.small), tiny:   map(videos.tiny)
            )
        )
    }
}

enum OLThumbnailRequestPriority {
    case visible
    case prefetch
}

actor OLThumbnailRequestCoordinator {
    static let shared = OLThumbnailRequestCoordinator()

    private let session: URLSession
    private let scheduler = OLThumbnailRequestScheduler()
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func loadData(from url: URL, priority: OLThumbnailRequestPriority) async -> Data? {
        let key = url.absoluteString
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<Data?, Never> { [session, scheduler] in
            defer { Task { await self.removeInFlightTask(forKey: key) } }
            return await scheduler.run(priority: priority) {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = priority == .visible ? 12 : 8
                    request.networkServiceType = priority == .visible ? .responsiveData : .background
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        return nil
                    }
                    return data
                } catch {
                    return nil
                }
            }
        }
        inFlight[key] = task
        return await task.value
    }

    private func removeInFlightTask(forKey key: String) {
        inFlight.removeValue(forKey: key)
    }
}

actor OLThumbnailRequestScheduler {
    private var activeVisibleRequests = 0
    private var activePrefetchRequests = 0
    private var waitingVisibleRequests: [CheckedContinuation<Void, Never>] = []
    private var waitingPrefetchRequests: [CheckedContinuation<Void, Never>] = []

    func run<T>(
        priority: OLThumbnailRequestPriority,
        operation: @Sendable () async -> T
    ) async -> T {
        await acquire(priority: priority)
        defer { release(priority: priority) }
        return await operation()
    }

    private func acquire(priority: OLThumbnailRequestPriority) async {
        while !canAcquire(priority: priority) {
            await withCheckedContinuation { continuation in
                switch priority {
                case .visible:
                    waitingVisibleRequests.append(continuation)
                case .prefetch:
                    waitingPrefetchRequests.append(continuation)
                }
            }
        }

        switch priority {
        case .visible:
            activeVisibleRequests += 1
        case .prefetch:
            activePrefetchRequests += 1
        }
    }

    private func canAcquire(priority: OLThumbnailRequestPriority) -> Bool {
        switch priority {
        case .visible:
            return activeVisibleRequests < 2
        case .prefetch:
            return activeVisibleRequests == 0
                && activePrefetchRequests == 0
                && waitingVisibleRequests.isEmpty
        }
    }

    private func release(priority: OLThumbnailRequestPriority) {
        switch priority {
        case .visible:
            activeVisibleRequests = max(0, activeVisibleRequests - 1)
        case .prefetch:
            activePrefetchRequests = max(0, activePrefetchRequests - 1)
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        while canAcquire(priority: .visible), !waitingVisibleRequests.isEmpty {
            let continuation = waitingVisibleRequests.removeFirst()
            continuation.resume()
        }

        if canAcquire(priority: .prefetch), let continuation = waitingPrefetchRequests.first {
            waitingPrefetchRequests.removeFirst()
            continuation.resume()
        }
    }
}

// MARK: - 服务

@MainActor
final class OnlineLibraryService: ObservableObject {
    static let shared = OnlineLibraryService()
    private enum Constants {
        static let initialThumbnailPrefetchLimit = 12
        static let visibleThumbnailPrefetchLeading = 6
        static let visibleThumbnailPrefetchTrailing = 12
        static let visibleThumbnailPrefetchLimit = 18
    }

    // MARK: 搜索状态
    @Published var items:        [OnlineLibraryVideoItem] = []
    @Published var isLoading:    Bool   = false
    @Published var errorMessage: String? = nil
    @Published var hasMore:      Bool   = false
    @Published var totalHits:    Int    = 0

    private(set) var currentParams = OnlineLibrarySearchParams()
    private var currentPage: Int = 1
    private(set) var hasLoadedOnce: Bool = false

    /// 重置「已加载」标记，使下次 triggerInitialSearchIfNeeded 重新触发搜索（如更换 API Key 后）
    func resetLoadedState() { hasLoadedOnce = false }

    /// 清空 API Key 并重置所有状态，切回登录界面
    func clearAPIKeyAndReset() {
        searchTask?.cancel()
        apiKey        = ""
        items         = []
        errorMessage  = nil
        isLoading     = false
        hasMore       = false
        hasLoadedOnce = false
        toolbarQuery  = ""
        lastThumbnailPrefetchIDSet.removeAll()
        objectWillChange.send()
    }

    // MARK: 工具栏驱动状态（工具栏写入，BrowserView 读取）
    @Published var toolbarCategory: OnlineLibraryCategory = .all
    @Published var toolbarQuery:    String = ""

    // MARK: 缩放（独立于视频库 gridZoomOffset，UserDefaults 持久化）
    @Published var zoomOffset: Int = UserDefaults.standard.integer(forKey: "onlineLibrary.gridZoomOffset") {
        didSet { UserDefaults.standard.set(zoomOffset, forKey: "onlineLibrary.gridZoomOffset") }
    }

    // MARK: API Key
    private static let apiKeyDefaultsKey = "OnlineLibraryAPIKey"
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyDefaultsKey); objectWillChange.send() }
    }
    var hasValidAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()
    private var searchTask: Task<Void, Never>?
    private var lastThumbnailPrefetchIDSet = Set<Int>()
    private init() {
        restoreDownloadedIDs()
    }

    /// 启动时扫描本地目录，将已存在的下载文件 ID 恢复到 downloadedIDs（OL-03）
    private func restoreDownloadedIDs() {
        let dir = Self.downloadDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        let ids = files.compactMap { url -> Int? in
            let name = url.lastPathComponent           // "online_12345.mp4"
            guard name.hasPrefix("online_"), name.hasSuffix(".mp4") else { return nil }
            let idStr = name
                .dropFirst("online_".count)
                .dropLast(".mp4".count)
            return Int(idStr)
        }
        downloadedIDs = Set(ids)
    }

    // MARK: - 公开接口

    func search(params: OnlineLibrarySearchParams) {
        searchTask?.cancel()
        currentParams = params
        currentPage   = 1
        items         = []
        errorMessage  = nil
        hasMore       = false
        hasLoadedOnce = true
        lastThumbnailPrefetchIDSet.removeAll()
        fetchPage(page: 1, appending: false)
    }

    func loadNextPage() {
        guard hasMore, !isLoading else { return }
        fetchPage(page: currentPage + 1, appending: true)
    }

    func prioritizeVisibleItemIDs(_ ids: [Int]) {
        guard !ids.isEmpty, !items.isEmpty else { return }
        var seen = Set<Int>()
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let visibleIndexes = uniqueIDs.compactMap { indexByID[$0] }.sorted()
        guard let firstVisibleIndex = visibleIndexes.first,
              let lastVisibleIndex = visibleIndexes.last else { return }
        let startIndex = max(0, firstVisibleIndex - Constants.visibleThumbnailPrefetchLeading)
        let endIndex = min(items.count - 1, lastVisibleIndex + Constants.visibleThumbnailPrefetchTrailing)
        guard startIndex <= endIndex else { return }
        prefetchThumbnailData(for: Array(items[startIndex...endIndex]), limit: Constants.visibleThumbnailPrefetchLimit)
    }

    // MARK: - 下载状态
    @Published var downloadingIDs: Set<Int> = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    @Published var downloadedIDs:  Set<Int> = []
    @Published var downloadError:  String?  = nil
    /// OL-04：仅下载完成后的成功提示（文件存储路径），UI 层消费后置 nil
    @Published var downloadSuccessMessage: String? = nil
    /// OL-04：最近下载完成的 item ID，供 Toast「设为壁纸」按钮使用
    @Published var lastDownloadedItemID: Int? = nil
    @Published private(set) var inspectedDownloadedItemID: Int? = nil
    /// 下载中途点「设为壁纸」时记录的待播放 ID，下载完成后自动触发（OL-06）
    private var pendingSetAfterDownload: Set<Int> = []

    var selectedDownloadedItemIDForInspector: Int? {
        inspectedDownloadedItemID
    }

    func presentInspectorForSelectedDownloadedItem(
        _ selectedID: Int?,
        isMultiSelectMode: Bool,
        availableIDs: Set<Int>
    ) {
        guard !isMultiSelectMode,
              let selectedID,
              availableIDs.contains(selectedID) else {
            return
        }
        inspectedDownloadedItemID = selectedID
    }

    func dismissSelectedDownloadedInspector() {
        inspectedDownloadedItemID = nil
    }

    func syncSelectedDownloadedInspectorIfNeeded(
        selectedID: Int?,
        isMultiSelectMode: Bool,
        availableIDs: Set<Int>
    ) {
        guard inspectedDownloadedItemID != nil else { return }
        guard !isMultiSelectMode,
              let selectedID,
              availableIDs.contains(selectedID) else {
            inspectedDownloadedItemID = nil
            return
        }
        inspectedDownloadedItemID = selectedID
    }

    /// 仅下载到本地，不触发播放
    func download(item: OnlineLibraryVideoItem) {
        startDownload(item: item, setAsWallpaperWhenDone: false)
    }

    /// 下载后设为壁纸：下载完成后发通知给 Shell 层（MainWindowCoordinator）中转，
    /// 由视频库静默导入并立即播放。在线库自身不依赖视频库模块，保持模块间零耦合。
    /// 通知名 onlineVideoReadyToPlay 定义在 Shell/ContentViewSupport.swift。
    func downloadAndSet(item: OnlineLibraryVideoItem) {
        // OL-05：文件已在本地，直接发通知，无需重新下载
        if downloadedIDs.contains(item.id) {
            postReadyToPlay(id: item.id)
            return
        }
        // OL-06：正在下载中，记录待播放，下载完成后自动触发
        if downloadingIDs.contains(item.id) {
            pendingSetAfterDownload.insert(item.id)
            return
        }
        pendingSetAfterDownload.insert(item.id)
        startDownload(item: item, setAsWallpaperWhenDone: true)
    }

    /// OL-05：已下载文件直接设为壁纸（从本地路径发通知，无需重新下载）
    private func postReadyToPlay(id: Int) {
        let local = Self.downloadDirectory.appendingPathComponent("online_\(id).mp4")
        guard FileManager.default.fileExists(atPath: local.path) else {
            // 文件不存在（可能被外部删除），移出已下载集合
            downloadedIDs.remove(id)
            return
        }
        NotificationCenter.default.post(
            name: .onlineVideoReadyToPlay,
            object: nil,
            userInfo: ["localURL": local]
        )
    }

    private func startDownload(item: OnlineLibraryVideoItem, setAsWallpaperWhenDone: Bool) {
        guard !downloadingIDs.contains(item.id), let url = item.bestVideoURL else { return }
        downloadingIDs.insert(item.id)
        downloadProgressByID[item.id] = 0
        Task {
            do {
                let local = try await fetchAndMove(
                    from: url,
                    name: "online_\(item.id).mp4",
                    itemID: item.id
                )
                downloadingIDs.remove(item.id)
                downloadProgressByID[item.id] = nil
                downloadedIDs.insert(item.id)
                if setAsWallpaperWhenDone || pendingSetAfterDownload.contains(item.id) {
                    pendingSetAfterDownload.remove(item.id)
                    NotificationCenter.default.post(
                        name: .onlineVideoReadyToPlay,
                        object: nil,
                        userInfo: ["localURL": local]
                    )
                } else {
                    lastDownloadedItemID = item.id
                    downloadSuccessMessage = "已保存到 \"影片/MyWallpaperX/在线图库\""
                }
            } catch {
                downloadingIDs.remove(item.id)
                downloadProgressByID[item.id] = nil
                pendingSetAfterDownload.remove(item.id)
                downloadError = error.localizedDescription
            }
        }
    }

    private func fetchAndMove(from url: URL, name: String, itemID: Int) async throws -> URL {
        let expectedBytes = await fetchRemoteFileSize(from: url)
        if let expectedBytes, expectedBytes > 0 {
            downloadProgressByID[itemID] = max(downloadProgressByID[itemID] ?? 0, 0.01)
        }
        let tmp = try await downloadFile(from: url, itemID: itemID, expectedBytes: expectedBytes)
        let dest = Self.downloadDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private func fetchRemoteFileSize(from url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return response.expectedContentLength > 0 ? response.expectedContentLength : nil
    }

    private func downloadFile(from url: URL, itemID: Int, expectedBytes: Int64?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = OLDownloadTaskDelegate(
                expectedBytes: expectedBytes ?? 0,
                progressHandler: { [weak self] progress in
                    self?.downloadProgressByID[itemID] = progress
                },
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            let downloadSession = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            let task = downloadSession.downloadTask(with: url)
            task.resume()
        }
    }

    func refresh() { search(params: currentParams) }

    // MARK: - 下载文件管理

    /// 返回本地下载目录
    static var downloadDirectory: URL {
        FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("在线图库",      isDirectory: true)
    }

    /// 扫描本地目录，返回所有已下载文件信息
    func loadDownloadedFiles() -> [OLLocalFile] {
        let dir = Self.downloadDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .compactMap { url -> OLLocalFile? in
                let name = url.lastPathComponent
                guard name.hasPrefix("online_") else { return nil }
                let attrs = (try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]))
                return OLLocalFile(
                    url:          url,
                    fileSize:     attrs?.fileSize ?? 0,
                    creationDate: attrs?.creationDate ?? Date()
                )
            }
            .sorted { $0.creationDate > $1.creationDate }  // 最新下载在最前
    }

    /// 删除本地已下载文件
    func deleteLocalFile(_ file: OLLocalFile) {
        try? FileManager.default.removeItem(at: file.url)
        // 从文件名反解 ID，移出 downloadedIDs
        let name = file.url.lastPathComponent
        let idStr = name.dropFirst("online_".count).dropLast(".mp4".count)
        if let id = Int(idStr) { downloadedIDs.remove(id) }
    }

    /// 从本地已下载文件直接设为壁纸（下载管理面板调用）
    func setLocalFileAsWallpaper(id: Int) {
        postReadyToPlay(id: id)
    }

    /// OL-12：便利搜索方法，用当前状态填充缺省值，消除调用方重复构建 OnlineLibrarySearchParams
    func searchWithCurrentContext(
        query:    String?                  = nil,
        category: OnlineLibraryCategory?   = nil,
        order:    OnlineLibraryOrder?      = nil
    ) {
        search(params: OnlineLibrarySearchParams(
            query:    query    ?? toolbarQuery,
            category: category ?? toolbarCategory,
            page:     1,
            perPage:  kOLDefaultPerPage,
            order:    order    ?? currentParams.order
        ))
    }

    // MARK: - 私有

    private func fetchPage(page: Int, appending: Bool) {
        guard hasValidAPIKey else { errorMessage = "请先填写 Pixabay API Key"; return }
        guard let url = buildURL(params: currentParams, page: page) else { errorMessage = "URL 构建失败"; return }

        isLoading    = true
        errorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await self.session.data(from: url)
                if Task.isCancelled { return }
                guard let http = response as? HTTPURLResponse else {
                    self.errorMessage = "无效响应"; self.isLoading = false; return
                }
                switch http.statusCode {
                case 200:
                    let decoded  = try JSONDecoder().decode(OLResponse.self, from: data)
                    let newItems = decoded.hits.map { $0.toItem() }
                    self.currentPage = page
                    self.totalHits   = decoded.totalHits
                    self.hasMore     = (page * self.currentParams.perPage) < decoded.totalHits
                    self.items       = appending ? self.items + newItems : newItems
                    self.prefetchThumbnailData(
                        for: appending ? newItems : self.items,
                        limit: Constants.initialThumbnailPrefetchLimit
                    )
                case 400:       self.errorMessage = "API Key 无效或不完整，请重新填写"
                case 401, 403:  self.errorMessage = "API Key 无效，请重新填写"
                case 429:       self.errorMessage = "请求过于频繁，请稍后再试"
                default:        self.errorMessage = "服务器错误 (\(http.statusCode))"
                }
            } catch is CancellationError {
                // 正常取消
            } catch {
                if !Task.isCancelled { self.errorMessage = "网络错误：\(error.localizedDescription)" }
            }
            self.isLoading = false
        }
    }

    private func buildURL(params: OnlineLibrarySearchParams, page: Int) -> URL? {
        var c = URLComponents(string: "https://pixabay.com/api/videos/")
        var q: [URLQueryItem] = [
            .init(name: "key",        value: apiKey),
            .init(name: "per_page",   value: "\(params.perPage)"),
            .init(name: "page",       value: "\(page)"),
            .init(name: "order",      value: params.order.rawValue),
            .init(name: "safesearch", value: "true")
        ]
        if !params.query.trimmingCharacters(in: .whitespaces).isEmpty {
            q.append(.init(name: "q", value: params.query))
        }
        if params.category != .all {
            q.append(.init(name: "category", value: params.category.rawValue))
        }
        c?.queryItems = q
        return c?.url
    }

    private func prefetchThumbnailData(for items: [OnlineLibraryVideoItem], limit: Int) {
        guard !items.isEmpty, limit > 0 else { return }
        let candidates = items.compactMap { item -> (Int, URL)? in
            guard let url = item.previewThumbnailURL else { return nil }
            return (item.id, url)
        }
        let limitedCandidates = Array(candidates.prefix(limit))
        let nextIDSet = Set(limitedCandidates.map(\.0))
        let deltaCandidates = limitedCandidates.filter { !lastThumbnailPrefetchIDSet.contains($0.0) }
        guard !deltaCandidates.isEmpty else { return }
        lastThumbnailPrefetchIDSet = nextIDSet

        for (_, url) in deltaCandidates {
            Task {
                guard await OLThumbnailCache.shared.cachedData(for: url) == nil else { return }
                guard let data = await OLThumbnailRequestCoordinator.shared.loadData(from: url, priority: .prefetch) else { return }
                await OLThumbnailCache.shared.store(data: data, for: url)
            }
        }
    }
}

// MARK: - 本地下载文件描述

struct OLLocalFile: Identifiable {
    let url:          URL
    let fileSize:     Int
    let creationDate: Date

    var id: URL { url }

    var displayName: String { url.lastPathComponent }

    var fileSizeString: String {
        let mb = Double(fileSize) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    var pixabayID: Int? {
        let name = url.lastPathComponent
        guard name.hasPrefix("online_"), name.hasSuffix(".mp4") else { return nil }
        return Int(name.dropFirst("online_".count).dropLast(".mp4".count))
    }
}

// MARK: - 缩略图磁盘缓存

actor OLThumbnailCache {
    static let shared = OLThumbnailCache()

    /// 缓存目录：~/Library/Caches/com.MyWallpaperX.OnlineLibrary/thumbnails/
    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("com.MyWallpaperX.OnlineLibrary/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 缓存有效期：7 天
    private let maxAge: TimeInterval = 7 * 24 * 3600
    /// 内存缓存（NSCache，自动响应内存压力，上限 60MB / 300 条）
    private let memCache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 300
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()

    private init() {
        Task { await self.evictExpired() }
    }

    /// 取缓存（内存 → 磁盘），返回 nil 表示无缓存
    func cachedData(for url: URL) -> Data? {
        let key = url.absoluteString as NSString
        if let data = memCache.object(forKey: key) { return data as Data }
        let file = cacheFile(for: url)
        guard FileManager.default.fileExists(atPath: file.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    /// 写入缓存
    func store(data: Data, for url: URL) {
        let key = url.absoluteString as NSString
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        let file = cacheFile(for: url)
        try? data.write(to: file, options: .atomic)
    }

    /// 删除 7 天前的缓存文件
    func evictExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap { $0.contentModificationDate } ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func cacheFile(for url: URL) -> URL {
        // URL → 安全文件名（用 base64 编码避免特殊字符）
        let name = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return cacheDir.appendingPathComponent(name)
    }
}
