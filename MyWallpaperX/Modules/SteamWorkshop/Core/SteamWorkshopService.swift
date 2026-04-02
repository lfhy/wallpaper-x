//
//  SteamWorkshopService.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Combine
import Security
import Darwin

enum SteamWorkshopSource: String, CaseIterable, Identifiable {
    case featured
    case recent
    case subscribed
    case updated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .featured: return "最热门"
        case .recent: return "最新"
        case .subscribed: return "最多订阅"
        case .updated: return "最后更新"
        }
    }

    var browseFilter: String {
        switch self {
        case .featured: return "trend"
        case .recent: return "mostrecent"
        case .subscribed: return "totaluniquesubscribers"
        case .updated: return "lastupdated"
        }
    }

    var supportsTimeRange: Bool {
        self == .featured
    }
}

enum SteamWorkshopTrendingWindow: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case quarter
    case halfYear
    case year
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "今天"
        case .week: return "一周"
        case .month: return "30 天"
        case .quarter: return "三个月"
        case .halfYear: return "半年"
        case .year: return "一年"
        case .allTime: return "有史以来"
        }
    }

    var daysValue: String {
        switch self {
        case .today: return "1"
        case .week: return "7"
        case .month: return "30"
        case .quarter: return "90"
        case .halfYear: return "180"
        case .year: return "365"
        case .allTime: return "-1"
        }
    }
}

enum SteamWorkshopThemeFilter: String, CaseIterable, Identifiable {
    case all
    case abstract = "Abstract"
    case anime = "Anime"
    case animal = "Animal"
    case city = "City"
    case technology = "Technology"
    case landscape = "Landscape"
    case space = "Space"
    case scifi = "Sci-Fi"
    case cgi = "CGI"
    case cyberpunk = "Cyberpunk"
    case fantasy = "Fantasy"
    case game = "Game"
    case movie = "Movie"
    case music = "Music"
    case nature = "Nature"
    case relaxing = "Relaxing"
    case cartoon = "Cartoon"
    case cute = "Cute"
    case vehicle = "Vehicle"
    case girls = "Girls"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部主题"
        case .abstract: return "抽象"
        case .anime: return "动漫"
        case .animal: return "动物"
        case .city: return "城市"
        case .technology: return "科技"
        case .landscape: return "风景"
        case .space: return "太空"
        case .scifi: return "科幻"
        case .cgi: return "CGI"
        case .cyberpunk: return "赛博朋克"
        case .fantasy: return "奇幻"
        case .game: return "游戏"
        case .movie: return "影视"
        case .music: return "音乐"
        case .nature: return "自然"
        case .relaxing: return "治愈"
        case .cartoon: return "卡通"
        case .cute: return "可爱"
        case .vehicle: return "载具"
        case .girls: return "人物"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopAgeRatingFilter: String, CaseIterable, Identifiable {
    case all
    case everyone = "Everyone"
    case mature = "Mature"
    case unspecified = "Unspecified"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部年龄"
        case .everyone: return "全年龄"
        case .mature: return "成人"
        case .unspecified: return "未标注"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopResolutionFilter: String, CaseIterable, Identifiable {
    case all
    case uhd4k = "3840 x 2160"
    case qhd = "2560 x 1440"
    case fhd = "1920 x 1080"
    case portrait4k = "2160 x 3840"
    case portrait2k = "1440 x 2560"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部分辨率"
        default: return rawValue
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case wallpaper = "Wallpaper"
    case scene = "Scene"
    case web = "Web"
    case application = "Application"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部分类"
        case .wallpaper: return "壁纸"
        case .scene: return "场景"
        case .web: return "网页"
        case .application: return "应用"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopBrowserLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum SteamWorkshopAuthenticationPhase: Equatable {
    case credentials
    case awaitingGuardCode
    case authenticated
}

enum SteamWorkshopPreviewAssetKind: String, Equatable, Codable {
    case unknown
    case stillImage
    case animatedImage
    case video

    var isAnimated: Bool {
        self == .animatedImage || self == .video
    }
}

struct SteamWorkshopDetailField: Identifiable, Equatable, Codable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}

struct SteamWorkshopBrowserItem: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let author: String
    let authorProfileURL: URL?
    let hasAdultContent: Bool
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let previewAssetKind: SteamWorkshopPreviewAssetKind
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let detailFields: [SteamWorkshopDetailField]
    let detailURL: URL

    var primaryMetaText: String {
        [fileSizeText, resolutionText]
            .compactMap { $0 }
            .joined(separator: "  ")
    }

    var secondaryMetaText: String {
        [workshopTypeText, ageRatingText, genreText, updatedText]
            .compactMap { $0 }
            .joined(separator: "  ")
    }
}

struct SteamWorkshopDownloadRecord: Identifiable, Equatable {
    enum Status: Equatable {
        case downloading
        case ready
        case failed(String)
    }

    let id: String
    let title: String
    let description: String
    let tags: [String]
    let folderURL: URL
    let previewURL: URL?
    let videoURL: URL?
    let updatedAt: Date
    let sizeText: String
    let status: Status

    var statusText: String {
        switch status {
        case .downloading:
            return "下载中"
        case .ready:
            return "已下载"
        case .failed:
            return "下载失败"
        }
    }
}

private struct SteamWorkshopProject: Decodable {
    let title: String?
    let description: String?
    let preview: String?
    let file: String?
    let tags: [String]?
    let workshopid: String?
    let type: String?
}

private struct SteamWorkshopDetailParseResult {
    let title: String
    let author: String
    let authorProfileURL: URL?
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let detailFields: [SteamWorkshopDetailField]
}

private struct SteamWorkshopBrowserCacheSnapshot: Codable {
    let fetchedAt: Date
    let items: [SteamWorkshopBrowserItem]
}

private struct SteamWorkshopBrowseStub: Equatable {
    let id: String
    let title: String?
    let author: String?
    let authorProfileURL: URL?
    let hasAdultContent: Bool
    let summary: String?
    let previewImageURL: URL?
}

private struct SteamWorkshopDetailCacheSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
}

private struct SteamWorkshopBundledRuntimeMetadata: Codable {
    let channel: String
    let version: String
    let releaseDate: String
    let notes: String
}

private struct SteamWorkshopPendingDownloadRequest {
    let id: String
    let pageTitle: String?
}

private enum SteamWorkshopDownloadControlError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消下载。"
        }
    }
}

private struct SteamWorkshopPTYSession {
    let master: FileHandle
    let slave: FileHandle
}

private enum SteamWorkshopCredentialStore {
    private static let service = "com.songziqiang.MyWallpaperX.steam"
    private static let account = "steamPassword"

    static func save(password: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            SecItemAdd(create as CFDictionary, nil)
        }
    }

    static func loadPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else {
            return nil
        }
        return password
    }

    static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class SteamWorkshopService: ObservableObject {
    static let shared = SteamWorkshopService()

    private enum Constants {
        static let workshopAppID = "431960"
        static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        static let bundledSteamBundleName = "SteamCMDRuntime.bundle"
        static let bundledSteamRootName = "Steam"
        static let bundledSteamMetadataName = "runtime-metadata.json"
        static let browserPageSize = 24
        static let cacheTTL: TimeInterval = 60 * 15
        static let detailCacheTTL: TimeInterval = 60 * 60 * 24
        static let defaultsLastUsername = "SteamWorkshop.lastUsername"
        static let defaultsLastAuthenticatedAt = "SteamWorkshop.lastAuthenticatedAt"
        static let requiredBundledItems = [
            "steamcmd.sh",
            "steamcmd",
            "steamclient.dylib",
            "libtier0_s.dylib",
            "libvstdlib_s.dylib",
            "crashhandler.dylib",
            "libaudio.dylib",
            "libsteaminput.dylib",
            "steamconsole.dylib",
            "update_hosts_cached.vdf",
            "package",
            "public",
            "Frameworks"
        ]
    }

    @Published private(set) var browserItems: [SteamWorkshopBrowserItem] = []
    @Published private(set) var browserState: SteamWorkshopBrowserLoadState = .idle
    @Published private(set) var isLoadingMoreBrowserItems = false
    @Published private(set) var hasMoreBrowserItems = true
    @Published private(set) var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var source: SteamWorkshopSource = .featured {
        didSet { navigateToBrowse() }
    }
    @Published var browserQuery: String = "" {
        didSet { navigateToBrowse() }
    }
    @Published var trendingWindow: SteamWorkshopTrendingWindow = .week {
        didSet { navigateToBrowse() }
    }
    @Published var themeFilter: SteamWorkshopThemeFilter = .all {
        didSet { navigateToBrowse() }
    }
    @Published var ageRatingFilter: SteamWorkshopAgeRatingFilter = .all {
        didSet { navigateToBrowse() }
    }
    @Published var resolutionFilter: SteamWorkshopResolutionFilter = .all {
        didSet { navigateToBrowse() }
    }
    @Published var categoryFilter: SteamWorkshopCategoryFilter = .all {
        didSet { navigateToBrowse() }
    }
    @Published var downloadsQuery: String = ""
    @Published var zoomOffset: Int = 0
    @Published var statusMessage: String = "浏览页使用原生网格展示，后台抓取 Wallpaper Engine 创意工坊视频信息。"
    @Published var currentWorkshopItemID: String?
    @Published var currentPageTitle: String = "Steam 创意工坊"
    @Published var requestedURL: URL
    @Published var navigationVersion: Int = 0
    @Published var activeDownloadItemID: String?
    @Published private(set) var activeDownloadProgressText: String?
    @Published private(set) var activeDownloadProgressFraction: Double?
    @Published var downloadError: String?
    @Published var selectedBrowserItem: SteamWorkshopBrowserItem?
    @Published private(set) var isRefreshingSelectedBrowserItem = false
    @Published var selectedBrowserItemError: String?
    @Published var requiresLogin: Bool = true
    @Published private(set) var isAnonymousBrowsing = false
    @Published private(set) var authPhase: SteamWorkshopAuthenticationPhase = .credentials
    @Published var isLoginSheetPresented = false
    @Published var isAuthenticating = false
    @Published private(set) var isPreparingRuntime = false
    @Published var authStatusMessage: String = "首次进入请登录 Steam，软件会使用随 App 打包的 SteamCMD 并保留登录态。"
    @Published var authError: String?
    @Published private(set) var steamRuntimeVersion: String = "未检测"
    @Published private(set) var steamRuntimeUpdateStatus: String = "当前使用 App 内置 SteamCMD 基线版本。"
    @Published var steamUsername: String = ""
    @Published var steamPassword: String = ""
    @Published var steamGuardCode: String = ""

    private var browserFetchTask: Task<Void, Never>?
    private var browserNextPage = 1
    private var prefetchedBrowserPageKeys = Set<String>()
    private let defaults = UserDefaults.standard
    private var loginProcess: Process?
    private var loginInputHandle: FileHandle?
    private var loginOutputHandle: FileHandle?
    private var loginOutputBuffer: String = ""
    private var loginPasswordSent = false
    private var loginSucceeded = false
    private var pendingLoginUsername: String = ""
    private var pendingLoginPassword: String = ""
    private var pendingLoginCommand: String?
    private var startupTask: Task<Void, Never>?
    private var loginBootstrapTimeoutTask: Task<Void, Never>?
    private var loginSessionID: String = ""
    private var pendingDownloadRequest: SteamWorkshopPendingDownloadRequest?
    private var activeDownloadProcess: Process?
    private var activeDownloadPipe: Pipe?
    private var activeDownloadMonitorTask: Task<Void, Never>?
    private var activeDownloadExpectedBytes: Int64?
    private var activeDownloadWasCancelled = false
    private var selectedItemDetailTask: Task<Void, Never>?

    private init() {
        requestedURL = SteamWorkshopService.makeBrowseURL(
            source: .featured,
            query: "",
            trendingWindow: .week,
            themeFilter: .all,
            ageRatingFilter: .all,
            resolutionFilter: .all,
            categoryFilter: .all,
            page: 1
        )
        loadAuthenticationState()
        refreshSteamRuntimeStatus()
        loadCachedBrowserItemsIfPossible()
        reloadInstalledItems()
        fetchBrowserItems()
    }

    var bundledSteamBundleURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent(Constants.bundledSteamBundleName, isDirectory: true)
    }

    var bundledSteamRootURL: URL? {
        bundledSteamBundleURL?
            .appendingPathComponent(Constants.bundledSteamRootName, isDirectory: true)
    }

    var bundledSteamCmdURL: URL? {
        bundledSteamRootURL?.appendingPathComponent("steamcmd.sh")
    }

    var activeSteamRootURL: URL? {
        guard let bundledSteamRootURL, validateSteamRuntime(at: bundledSteamRootURL) else {
            return nil
        }
        return bundledSteamRootURL
    }

    var activeSteamCmdURL: URL? {
        guard let bundledSteamCmdURL,
              let bundledSteamRootURL,
              validateSteamRuntime(at: bundledSteamRootURL) else {
            return nil
        }
        return bundledSteamCmdURL
    }

    var runtimeInstallRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopRuntime", isDirectory: true)
    }

    var stagingWorkshopContentRootURL: URL {
        runtimeInstallRootURL
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("workshop", isDirectory: true)
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
    }

    var libraryRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("创意工坊", isDirectory: true)
    }

    var cacheDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
    }

    var steamAuthDebugLogURL: URL {
        cacheDirectoryURL.appendingPathComponent("steamcmd-auth-debug.log")
    }

    var bundledSteamMetadataURL: URL? {
        bundledSteamBundleURL?
            .appendingPathComponent(Constants.bundledSteamMetadataName)
    }

    var filteredDownloads: [SteamWorkshopDownloadRecord] {
        let query = downloadsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return downloads }
        let normalized = query.localizedLowercase
        return downloads.filter {
            $0.title.localizedLowercase.contains(normalized)
            || $0.description.localizedLowercase.contains(normalized)
            || $0.tags.contains(where: { $0.localizedLowercase.contains(normalized) })
            || $0.id.localizedLowercase.contains(normalized)
        }
    }

    var downloadsCount: Int { downloads.count }

    var activeFilterDisplayParts: [String] {
        var parts: [String] = []
        if themeFilter != .all { parts.append(themeFilter.displayName) }
        if ageRatingFilter != .all { parts.append(ageRatingFilter.displayName) }
        if resolutionFilter != .all { parts.append(resolutionFilter.displayName) }
        if categoryFilter != .all { parts.append(categoryFilter.displayName) }
        return parts
    }

    var activeFilterSummary: String {
        let parts = activeFilterDisplayParts
        return parts.isEmpty ? "未筛选" : parts.joined(separator: " · ")
    }

    func isDownloading(itemID: String) -> Bool {
        activeDownloadItemID == itemID
    }

    func downloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        downloads.first(where: { $0.id == itemID && $0.status == .ready })
    }

    func isDownloaded(itemID: String) -> Bool {
        downloadRecord(for: itemID) != nil
    }

    func downloadProgressLabel(for itemID: String) -> String? {
        guard activeDownloadItemID == itemID else { return nil }
        return activeDownloadProgressText
    }

    func navigateToBrowse() {
        requestedURL = Self.makeBrowseURL(
            source: source,
            query: browserQuery,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: 1
        )
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
        fetchBrowserItems()
    }

    func refresh() {
        navigationVersion += 1
        reloadInstalledItems()
        fetchBrowserItems(forceRefresh: true)
    }

    func loadMoreBrowserItemsIfNeeded() {
        guard !isLoadingMoreBrowserItems, hasMoreBrowserItems, browserState == .loaded else { return }

        let source = self.source
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter
        let page = browserNextPage

        isLoadingMoreBrowserItems = true

        Task(priority: .userInitiated) { [weak self] in
            do {
                let stubs = try await Self.fetchWorkshopStubs(
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: page
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    let existingIDs = Set(self.browserItems.map(\.id))
                    let fallbackItems = stubs
                        .map(Self.fallbackBrowserItem)
                        .filter { !existingIDs.contains($0.id) }
                    self.browserItems.append(contentsOf: fallbackItems)
                    self.statusMessage = "已预加载第 \(page) 页基础卡片，正在补全详细信息…"
                }
                let items = try await Self.fetchWorkshopItems(stubs: stubs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.mergeBrowserItems(items)
                    self.browserNextPage = page + 1
                    self.hasMoreBrowserItems = stubs.count >= Constants.browserPageSize
                    self.isLoadingMoreBrowserItems = false
                    self.statusMessage = self.hasMoreBrowserItems
                        ? "已加载 \(self.browserItems.count) 个创意工坊视频项目"
                        : "已加载全部 \(self.browserItems.count) 个已抓取项目"
                    self.saveBrowserCache(
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        items: self.browserItems
                    )
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = false
                }
            }
        }
    }

    func clearFilters() {
        themeFilter = .all
        ageRatingFilter = .all
        resolutionFilter = .all
        categoryFilter = .all
    }

    func prepareForBrowserEntry() {
        startupTask?.cancel()
        startupTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.prepareRuntimeIfNeeded()
        }
    }

    func presentItemDetail(_ item: SteamWorkshopBrowserItem) {
        selectedBrowserItem = item
        selectedBrowserItemError = nil
        currentWorkshopItemID = item.id
        currentPageTitle = item.title
        statusMessage = "已加载 \(item.title)"
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: needsDetailRefresh(for: item))
    }

    func dismissItemDetail() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
    }

    func retrySelectedBrowserItemDetailRefresh() {
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
    }

    func authenticateUser() {
        Task { @MainActor [weak self] in
            self?.authenticateUserImmediately()
        }
    }

    private func authenticateUserImmediately() {
        guard !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authError = "请输入 Steam 用户名。"
            return
        }
        guard !steamPassword.isEmpty else {
            authError = "请输入 Steam 密码。"
            return
        }

        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = steamPassword
        cancelActiveLoginSession()
        isAnonymousBrowsing = false
        authPhase = .credentials
        isAuthenticating = true
        authError = nil
        authStatusMessage = "正在启动内置 SteamCMD，并向 Steam 发起登录请求…"

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.beginInteractiveSteamLogin(username: username, password: password)
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func submitSteamGuardCode() {
        Task { @MainActor [weak self] in
            self?.submitSteamGuardCodeImmediately()
        }
    }

    private func submitSteamGuardCodeImmediately() {
        let guardCode = steamGuardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authPhase == .awaitingGuardCode else {
            authError = "当前没有等待输入的 Steam Guard 验证。"
            return
        }
        guard !guardCode.isEmpty else {
            authError = "请输入 Steam Guard 令牌。"
            return
        }
        guard let inputHandle = loginInputHandle else {
            authError = "登录会话已失效，请重新输入账号和密码。"
            authPhase = .credentials
            isAuthenticating = false
            return
        }

        authError = nil
        isAuthenticating = true
        authStatusMessage = "正在验证 Steam Guard 令牌…"
        inputHandle.write(Data("\(guardCode)\r".utf8))
    }

    func browseAnonymously() {
        Task { @MainActor [weak self] in
            self?.browseAnonymouslyImmediately()
        }
    }

    private func browseAnonymouslyImmediately() {
        cancelActiveLoginSession()
        requiresLogin = !hasSavedCredentials
        isAnonymousBrowsing = true
        authPhase = .credentials
        authError = nil
        isAuthenticating = false
        isLoginSheetPresented = false
        authStatusMessage = "当前为匿名浏览模式：可以查看创意工坊视频列表，下载前需要先登录 Steam。"
        fetchBrowserItems()
    }

    func presentLoginGate() {
        Task { @MainActor [weak self] in
            self?.presentLoginGateImmediately()
        }
    }

    private func presentLoginGateImmediately() {
        cancelActiveLoginSession()
        authPhase = .credentials
        isAuthenticating = false
        steamGuardCode = ""
        authError = nil
        isLoginSheetPresented = false

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isPreparingRuntime = true
                self.authStatusMessage = "正在准备 SteamCMD 运行环境…"
            }

            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authStatusMessage = "请输入 Steam 账号密码。若 Steam 要求验证，下一步再填写 Guard 令牌。"
                    self.isLoginSheetPresented = true
                }
            } catch {
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func logout() {
        Task { @MainActor [weak self] in
            self?.logoutImmediately()
        }
    }

    private func logoutImmediately() {
        cancelActiveLoginSession()
        cancelDownloadImmediately(showFeedback: false)
        defaults.removeObject(forKey: Constants.defaultsLastUsername)
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.deletePassword()
        pendingDownloadRequest = nil
        steamUsername = ""
        steamPassword = ""
        steamGuardCode = ""
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "已退出当前 Steam 登录态。"
    }

    func downloadWorkshopItem(id: String, pageTitle: String? = nil) {
        guard activeDownloadItemID == nil else {
            statusMessage = "已有下载任务在执行，请稍候。"
            return
        }

        guard !requiresLogin && hasSavedCredentials else {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            authStatusMessage = "下载需要登录 Steam。请先完成登录，成功后会自动继续刚才的下载。"
            presentLoginGate()
            return
        }

        statusMessage = "正在确认 Steam 下载环境…"

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureManagedSteamRuntime()
                try await self.performWorkshopDownload(id: id, pageTitle: pageTitle)
            } catch {
                await MainActor.run {
                    self.finishActiveDownloadState()
                    let message = error.localizedDescription
                    if error is SteamWorkshopDownloadControlError {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message), sizeText: "已取消")
                        return
                    }
                    let nsError = error as NSError
                    if nsError.domain == "SteamWorkshop", nsError.code == 11 {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed("登录已过期"), sizeText: "等待重新登录")
                        return
                    }
                    self.cleanupStagedDownload(id: id)
                    self.downloadError = message
                    self.statusMessage = message
                    self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
                }
            }
        }
    }

    func cancelActiveDownload() {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(showFeedback: true)
        }
    }

    func reloadInstalledItems() {
        let fileManager = FileManager.default
        let root = libraryRootURL
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloads = downloads.filter {
                if case .downloading = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }
            return
        }

        var records: [SteamWorkshopDownloadRecord] = []
        for directory in directories where directory.hasDirectoryPath {
            guard let record = buildInstalledRecord(at: directory) else { continue }
            records.append(record)
        }

        let transient = downloads.filter { record in
            switch record.status {
            case .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
    }

    func revealDownloadsDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryRootURL])
    }

    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) {
        NSWorkspace.shared.open(item.detailURL)
    }

    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) {
        guard let authorProfileURL = item.authorProfileURL else { return }
        guard var components = URLComponents(url: authorProfileURL.appendingPathComponent("myworkshopfiles"), resolvingAgainstBaseURL: false) else {
            NSWorkspace.shared.open(authorProfileURL)
            return
        }
        components.queryItems = [URLQueryItem(name: "appid", value: Constants.workshopAppID)]
        NSWorkspace.shared.open(components.url ?? authorProfileURL)
    }

    func revealItem(_ record: SteamWorkshopDownloadRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.folderURL])
    }

    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) {
        guard let videoURL = record.videoURL else {
            downloadError = "没有找到可播放的视频文件。"
            return
        }
        NotificationCenter.default.post(
            name: .steamWorkshopVideoReadyToPlay,
            object: nil,
            userInfo: ["localURL": videoURL]
        )
        statusMessage = "已将 \(record.title) 发送到视频库并准备播放"
    }

    private func loadAuthenticationState() {
        let storedUsername = defaults.string(forKey: Constants.defaultsLastUsername) ?? ""
        let storedPassword = SteamWorkshopCredentialStore.loadPassword() ?? ""
        steamUsername = storedUsername
        steamPassword = storedPassword
        requiresLogin = storedUsername.isEmpty || storedPassword.isEmpty
        isAnonymousBrowsing = requiresLogin
        authPhase = requiresLogin ? .credentials : .authenticated
        if requiresLogin {
            authStatusMessage = "当前还没有可复用的 Steam 登录凭据。可以先匿名浏览，需要下载时再登录。"
        } else if let lastAuthenticatedAt = defaults.object(forKey: Constants.defaultsLastAuthenticatedAt) as? Date {
            authStatusMessage = "已检测到上次成功登录的 Steam 凭据。下载时会优先直接复用；如果远端会话已失效，再提示你重新登录。上次成功登录时间：\(lastAuthenticatedAt.formatted(date: .abbreviated, time: .shortened))。"
        } else {
            authStatusMessage = "已检测到可复用的 Steam 凭据。下载时会优先直接复用；如果远端会话已失效，再提示你重新登录。"
        }
    }

    private func saveAuthenticationState(username: String, password: String) {
        defaults.set(username, forKey: Constants.defaultsLastUsername)
        defaults.set(Date(), forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.save(password: password)
        requiresLogin = false
        isAnonymousBrowsing = false
        authPhase = .authenticated
    }

    private var hasSavedCredentials: Bool {
        !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steamPassword.isEmpty
    }

    private func prepareRuntimeIfNeeded() async {
        await MainActor.run {
            self.isPreparingRuntime = true
            self.statusMessage = "正在检查 SteamCMD 环境…"
        }

        do {
            try await ensureManagedSteamRuntime()
            await MainActor.run {
                self.isPreparingRuntime = false
                if self.browserState == .idle {
                    self.statusMessage = "SteamCMD 环境已就绪，正在加载创意工坊列表…"
                }
            }
        } catch {
            await MainActor.run {
                self.isPreparingRuntime = false
                self.requiresLogin = true
                self.isAnonymousBrowsing = true
                self.authPhase = .credentials
                self.authError = error.localizedDescription
                self.authStatusMessage = "SteamCMD 环境准备失败。"
            }
            return
        }
    }

    private func performWorkshopDownload(id: String, pageTitle: String?) async throws {
        let title = pageTitle ?? "Workshop #\(id)"
        let expectedBytes = expectedDownloadBytes(for: id)
        statusMessage = "正在通过内置 SteamCMD 下载 \(title)"

        let output: String
        do {
            output = try await runDownloadProcess(
                id: id,
                title: title,
                expectedBytes: expectedBytes,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", steamUsername, steamPassword,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        } catch {
            let processOutput = error.localizedDescription
            if outputIndicatesAuthenticationFailure(processOutput) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请重新输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请重新登录。登录成功后会自动继续下载。"
                ])
            }
            throw error
        }

        guard output.localizedCaseInsensitiveContains("Success. Downloaded item") else {
            if outputIndicatesAuthenticationFailure(output) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请重新输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请重新登录。登录成功后会自动继续下载。"
                ])
            }
            throw NSError(domain: "SteamWorkshop", code: 2, userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 未返回成功下载结果。" : output
            ])
        }

        try syncDownloadedItemToLibrary(id: id)

        finishActiveDownloadState()
        statusMessage = "已完成 Workshop #\(id) 下载"
        reloadInstalledItems()
    }

    private func ensureManagedSteamRuntime() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: libraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeInstallRootURL, withIntermediateDirectories: true)

        guard let bundledSteamRootURL,
              validateSteamRuntime(at: bundledSteamRootURL) else {
            throw NSError(domain: "SteamWorkshop", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "App 包内没有找到可用的 SteamCMD 基线资源。"
            ])
        }

        steamRuntimeUpdateStatus = "当前直接运行 App 内置 SteamCMD 基线版本。后续 SteamCMD 升级将随应用更新一起分发。"
    }

    private func runSteamProcess(arguments: [String], stdinText: String? = nil) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.currentDirectoryURL = steamRootURL
            process.arguments = ["./steamcmd.sh"] + arguments
            process.environment = steamProcessEnvironment()

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            let inputPipe = Pipe()
            process.standardInput = inputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                    ]))
                }
            }

            do {
                try process.run()
                if let stdinText, !stdinText.isEmpty {
                    inputPipe.fileHandleForWriting.write(Data(stdinText.utf8))
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runDownloadProcess(
        id: String,
        title: String,
        expectedBytes: Int64?,
        arguments: [String]
    ) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"] + arguments
        process.environment = steamProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        activeDownloadWasCancelled = false

        return try await withCheckedThrowingContinuation { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD STDOUT: \(self?.sanitizeSteamOutput(chunk) ?? "")")
                }
            }

            process.terminationHandler = { [weak self] process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                Task { @MainActor [weak self] in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    self?.stopDownloadMonitor()
                    self?.activeDownloadProcess = nil
                    self?.activeDownloadPipe = nil
                    if self?.activeDownloadWasCancelled == true {
                        continuation.resume(throwing: SteamWorkshopDownloadControlError.cancelled)
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                        ]))
                    }
                }
            }

            do {
                try process.run()
                Task { @MainActor [weak self] in
                    self?.startActiveDownloadState(
                        id: id,
                        title: title,
                        expectedBytes: expectedBytes,
                        process: process,
                        pipe: outputPipe
                    )
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func startActiveDownloadState(
        id: String,
        title: String,
        expectedBytes: Int64?,
        process: Process,
        pipe: Pipe
    ) {
        activeDownloadItemID = id
        activeDownloadProcess = process
        activeDownloadPipe = pipe
        activeDownloadExpectedBytes = expectedBytes
        activeDownloadProgressFraction = 0
        activeDownloadProgressText = expectedBytes.map { "0 MB / \(Self.fileSizeText(forBytes: $0))" } ?? "0 MB"
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: activeDownloadProgressText ?? "0 MB")
        startDownloadMonitor(for: id)
    }

    private func finishActiveDownloadState() {
        stopDownloadMonitor()
        activeDownloadProcess = nil
        activeDownloadPipe = nil
        activeDownloadExpectedBytes = nil
        activeDownloadItemID = nil
        activeDownloadProgressFraction = nil
        activeDownloadProgressText = nil
        activeDownloadWasCancelled = false
    }

    private func cancelDownloadImmediately(showFeedback: Bool) {
        guard activeDownloadProcess != nil || activeDownloadItemID != nil else { return }
        activeDownloadWasCancelled = true
        activeDownloadProcess?.terminate()
        stopDownloadMonitor()
        if showFeedback {
            statusMessage = "正在取消当前下载…"
        }
    }

    private func startDownloadMonitor(for id: String) {
        stopDownloadMonitor()
        activeDownloadMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshDownloadProgress(for: id)
                }
            }
        }
    }

    private func stopDownloadMonitor() {
        activeDownloadMonitorTask?.cancel()
        activeDownloadMonitorTask = nil
    }

    private func refreshDownloadProgress(for id: String) {
        guard activeDownloadItemID == id else { return }
        let downloadedBytes = directorySize(at: stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true))
        let downloadedText = Self.fileSizeText(forBytes: downloadedBytes)
        if let expectedBytes = activeDownloadExpectedBytes, expectedBytes > 0 {
            let fraction = min(max(Double(downloadedBytes) / Double(expectedBytes), 0), 1)
            activeDownloadProgressFraction = fraction
            activeDownloadProgressText = "\(downloadedText) / \(Self.fileSizeText(forBytes: expectedBytes))"
        } else {
            activeDownloadProgressFraction = nil
            activeDownloadProgressText = downloadedText
        }

        if let title = browserItems.first(where: { $0.id == id })?.title
            ?? selectedBrowserItem?.title
            ?? downloads.first(where: { $0.id == id })?.title {
            upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: activeDownloadProgressText ?? downloadedText)
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func cleanupStagedDownload(id: String) {
        let stagedURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try? FileManager.default.removeItem(at: stagedURL)
        }
    }

    private func expectedDownloadBytes(for id: String) -> Int64? {
        if let item = browserItems.first(where: { $0.id == id }) {
            return Self.parseByteCount(from: item.fileSizeText)
        }
        if selectedBrowserItem?.id == id {
            return Self.parseByteCount(from: selectedBrowserItem?.fileSizeText)
        }
        return nil
    }

    private func expireAuthenticationAndPromptRelogin(
        reason: String,
        pendingDownload: SteamWorkshopPendingDownloadRequest?
    ) {
        cancelActiveLoginSession()
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.deletePassword()
        steamPassword = ""
        steamGuardCode = ""
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        authError = nil
        authStatusMessage = reason
        self.pendingDownloadRequest = pendingDownload
        isLoginSheetPresented = true
    }

    private func syncDownloadedItemToLibrary(id: String) throws {
        let fileManager = FileManager.default
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        let targetURL = libraryRootURL.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "SteamWorkshop", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到下载结果目录。"
            ])
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }

    private func fetchBrowserItems(forceRefresh: Bool = false) {
        browserFetchTask?.cancel()
        browserNextPage = 2
        hasMoreBrowserItems = true
        isLoadingMoreBrowserItems = false
        prefetchedBrowserPageKeys.removeAll()
        let source = self.source
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter

        if let cached = loadBrowserCache(
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter
        ) {
            browserItems = cached.items
            browserState = .loaded
            hasMoreBrowserItems = cached.items.count >= Constants.browserPageSize
            browserNextPage = max(2, (cached.items.count / Constants.browserPageSize) + 1)
            statusMessage = "已载入缓存的创意工坊列表"
            if !forceRefresh && Date().timeIntervalSince(cached.fetchedAt) < Constants.cacheTTL {
                return
            }
        } else {
            browserState = .loading
            browserItems = []
            statusMessage = "正在抓取 Wallpaper Engine 创意工坊视频列表…"
        }

        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let stubs = try await Self.fetchWorkshopStubs(
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: 1
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.browserItems = stubs.map(Self.fallbackBrowserItem)
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = stubs.count >= Constants.browserPageSize
                    self.browserNextPage = 2
                    self.statusMessage = self.browserItems.isEmpty
                        ? "没有抓取到符合条件的视频项目。"
                        : "已载入 \(self.browserItems.count) 张基础卡片，正在补全详情…"
                }
                let items = try await Self.fetchWorkshopItems(stubs: stubs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.mergeBrowserItems(items)
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = stubs.count >= Constants.browserPageSize
                    self.browserNextPage = 2
                    self.isLoadingMoreBrowserItems = false
                    self.statusMessage = items.isEmpty
                        ? "没有抓取到符合条件的视频项目。"
                        : "已加载 \(items.count) 个创意工坊视频项目"
                    self.saveBrowserCache(
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        items: items
                    )
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    if self.browserItems.isEmpty {
                        self.browserState = .failed(error.localizedDescription)
                    }
                    self.statusMessage = "创意工坊列表抓取失败"
                }
            }
        }
    }

    private func beginInteractiveSteamLogin(username: String, password: String) {
        resetSteamAuthDebugLog()
        loginSessionID = UUID().uuidString.lowercased()
        appendSteamAuthDebugLog("=== Steam login session started ===")
        appendSteamAuthDebugLog("Session ID: \(loginSessionID)")
        appendSteamAuthDebugLog("Local time: \(Date().formatted(date: .complete, time: .standard))")
        appendSteamAuthDebugLog("Bundle path: \(Bundle.main.bundleURL.path)")
        appendSteamAuthDebugLog("Log file path: \(steamAuthDebugLogURL.path)")
        appendSteamAuthDebugLog("Execution mode: app -> /bin/bash ./steamcmd.sh")
        pendingLoginUsername = username
        pendingLoginPassword = password
        pendingLoginCommand = "login \(username) \(password)\r"
        appendSteamAuthDebugLog("Prepared command: \(redactedLoginCommand(username: username, password: password))")
        steamGuardCode = ""
        loginPasswordSent = false
        loginSucceeded = false
        loginOutputBuffer = ""

        let process = Process()
        let steamRootURL: URL
        do {
            steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
            appendSteamAuthDebugLog("Resolved runtime root: \(steamRootURL.path)")
        } catch {
            appendSteamAuthDebugLog("Failed to resolve runtime root: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        let pty: SteamWorkshopPTYSession
        do {
            pty = try makeSteamPTYSession()
            appendSteamAuthDebugLog("Created local PTY session for interactive login.")
        } catch {
            appendSteamAuthDebugLog("Failed to create local PTY: \(error.localizedDescription)")
            isAuthenticating = false
            authError = "无法创建 SteamCMD 交互会话。"
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"]
        process.environment = steamProcessEnvironment()
        process.standardInput = pty.slave
        process.standardOutput = pty.slave
        process.standardError = pty.slave
        appendSteamAuthDebugLog("Launch path: /bin/bash")
        appendSteamAuthDebugLog("Launch arguments: ./steamcmd.sh")

        pty.master.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                self?.handleInteractiveLoginOutput(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.appendSteamAuthDebugLog("Process terminated with status \(process.terminationStatus).")
                try? pty.master.close()
                try? pty.slave.close()
                self?.handleInteractiveLoginTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            appendSteamAuthDebugLog("Process started successfully.")
            loginProcess = process
            loginInputHandle = pty.master
            loginOutputHandle = pty.master
            authStatusMessage = "SteamCMD 已启动，正在等待控制台就绪…"
            loginBootstrapTimeoutTask?.cancel()
            loginBootstrapTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          !self.loginPasswordSent,
                          self.authPhase == .credentials else { return }
                    self.appendSteamAuthDebugLog("Bootstrap timeout reached before Steam prompt was observed.")
                    self.finalizeInteractiveLoginFailure(message: "SteamCMD 控制台未进入可登录状态，登录命令没有被执行。")
                }
            }
        } catch {
            try? pty.master.close()
            try? pty.slave.close()
            appendSteamAuthDebugLog("Process start failed: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
        }
    }

    private func handleInteractiveLoginOutput(_ chunk: String) {
        loginOutputBuffer.append(chunk)
        let lowered = loginOutputBuffer.localizedLowercase
        appendSteamAuthDebugLog("STDOUT chunk: \(sanitizeSteamOutput(chunk))")

        if lowered.contains("createboundsocket") {
            appendSteamAuthDebugLog("Observed network socket bind failure while SteamCMD attempted to connect.")
        }

        if lowered.contains("error (no connection)") {
            appendSteamAuthDebugLog("SteamCMD reported ERROR (No Connection) and returned to the Steam prompt.")
        }

        if !loginPasswordSent,
           lowered.contains("steam>") {
            appendSteamAuthDebugLog("Detected Steam prompt. About to send login command.")
            sendPendingLoginCommandIfPossible()
        }

        if authPhase != .awaitingGuardCode, outputRequestsGuardCode(lowered) {
            authPhase = .awaitingGuardCode
            isAuthenticating = false
            authStatusMessage = "Steam 已要求进行 Steam Guard 验证，请输入刚收到的令牌。"
            return
        }

        if outputIndicatesLoginSuccess(lowered) {
            finalizeInteractiveLoginSuccess()
            return
        }

        if loginPasswordSent && authPhase != .awaitingGuardCode && outputIndicatesAuthenticationFailure(chunk) {
            finalizeInteractiveLoginFailure(message: loginOutputBuffer)
        }
    }

    private func handleInteractiveLoginTermination(status: Int32) {
        loginOutputHandle?.readabilityHandler = nil
        appendSteamAuthDebugLog("Handling process termination. status=\(status), loginSucceeded=\(loginSucceeded), authPhase=\(authPhase)")

        if loginSucceeded {
            cancelActiveLoginSession(keepStatus: true)
            return
        }

        if authPhase == .awaitingGuardCode {
            finalizeInteractiveLoginFailure(message: "Steam Guard 验证会话已结束，请重新输入账号和密码。")
            return
        }

        if status == 0, outputIndicatesLoginSuccess(loginOutputBuffer.localizedLowercase) {
            finalizeInteractiveLoginSuccess()
            return
        }

        let message = loginOutputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        finalizeInteractiveLoginFailure(message: message.isEmpty ? "Steam 登录失败，请检查账号密码是否正确。" : message)
    }

    private func finalizeInteractiveLoginSuccess() {
        guard !loginSucceeded else { return }
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked successful.")
        loginSucceeded = true
        saveAuthenticationState(username: pendingLoginUsername, password: pendingLoginPassword)
        steamGuardCode = ""
        isAuthenticating = false
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "Steam 登录已建立。当前会记住你的凭据，后续下载会优先直接复用；如果远端会话失效，再提示重新登录。"
        loginInputHandle?.write(Data("quit\r".utf8))
        fetchBrowserItems()
        let pendingDownload = pendingDownloadRequest
        pendingDownloadRequest = nil
        if let pendingDownload {
            DispatchQueue.main.async {
                SteamWorkshopService.shared.downloadWorkshopItem(
                    id: pendingDownload.id,
                    pageTitle: pendingDownload.pageTitle
                )
            }
        }
    }

    private func finalizeInteractiveLoginFailure(message: String) {
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked failed: \(sanitizeSteamOutput(message))")
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        isAuthenticating = false
        authError = message.trimmingCharacters(in: .whitespacesAndNewlines)
        authStatusMessage = "Steam 登录失败，请重新输入账号密码后再试。"
        cancelActiveLoginSession(keepStatus: true)
    }

    private func cancelActiveLoginSession(keepStatus: Bool = false) {
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
        appendSteamAuthDebugLog("Cancelling login session. keepStatus=\(keepStatus)")
        loginOutputHandle?.readabilityHandler = nil
        try? loginOutputHandle?.close()
        try? loginInputHandle?.close()
        if let process = loginProcess, process.isRunning {
            process.terminate()
        }
        loginProcess = nil
        loginInputHandle = nil
        loginOutputHandle = nil
        loginOutputBuffer = ""
        loginPasswordSent = false
        loginSucceeded = false
        pendingLoginUsername = ""
        pendingLoginPassword = ""
        pendingLoginCommand = nil
        if !keepStatus, authPhase != .authenticated {
            authPhase = .credentials
        }
    }

    private func sendPendingLoginCommandIfPossible() {
        guard !loginPasswordSent,
              let command = pendingLoginCommand,
              let loginInputHandle else { return }
        appendSteamAuthDebugLog("Writing login command to PTY: \(redactedCommand(command))")
        loginInputHandle.write(Data(command.utf8))
        loginPasswordSent = true
        authStatusMessage = "SteamCMD 控制台已就绪，正在向 Steam 发起账号登录请求…"
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
    }

    private func resetSteamAuthDebugLog() {
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? Data().write(to: steamAuthDebugLogURL, options: [.atomic])
    }

    private func appendSteamAuthDebugLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))][session:\(loginSessionID.isEmpty ? "n/a" : loginSessionID)] \(message)\n"
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: steamAuthDebugLogURL.path),
               let handle = try? FileHandle(forWritingTo: steamAuthDebugLogURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: steamAuthDebugLogURL, options: [.atomic])
            }
        }
    }

    private func redactedLoginCommand(username: String, password: String) -> String {
        "login \(username) \(String(repeating: "*", count: max(8, password.count)))\\r"
    }

    private func redactedCommand(_ command: String) -> String {
        if command.hasPrefix("login ") {
            let parts = command.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 {
                return "login \(parts[1]) \(String(repeating: "*", count: 8))\\r"
            }
        }
        return sanitizeSteamOutput(command)
    }

    private func sanitizeSteamOutput(_ text: String) -> String {
        let sanitizedLogin = text.replacingOccurrences(
            of: #"login\s+(\S+)\s+([^\r\n]+)"#,
            with: "login $1 ********",
            options: .regularExpression
        )

        return sanitizedLogin
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateSteamRuntime(at rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard Constants.requiredBundledItems.allSatisfy({ name in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path)
        }) else {
            return false
        }

        for executableName in ["steamcmd.sh", "steamcmd"] {
            let executablePath = rootURL.appendingPathComponent(executableName).path
            guard fileManager.isExecutableFile(atPath: executablePath) else {
                return false
            }
        }
        return true
    }

    private func makeSteamPTYSession() throws -> SteamWorkshopPTYSession {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
            )
        }

        return SteamWorkshopPTYSession(
            master: FileHandle(fileDescriptor: masterFD, closeOnDealloc: true),
            slave: FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        )
    }

    private func resolvedSteamRuntimeExecutionRootURL() throws -> URL {
        if let activeSteamRootURL {
            return activeSteamRootURL
        }
        throw NSError(domain: "SteamWorkshop", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "内置 SteamCMD 运行目录无效，未执行任何旧缓存回退。请确认应用包中的 SteamCMDRuntime.bundle 完整存在。"
        ])
    }

    private func steamProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        return environment
    }

    private func refreshSteamRuntimeStatus() {
        if let metadataURL = bundledSteamMetadataURL,
           let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SteamWorkshopBundledRuntimeMetadata.self, from: data) {
            steamRuntimeVersion = metadata.version
            steamRuntimeUpdateStatus = "当前内置基线版本为 \(metadata.version)。运行时直接使用 App 内置 SteamCMD，后续版本更新随应用更新一起分发。"
        } else {
            steamRuntimeVersion = "未知"
            steamRuntimeUpdateStatus = "未读取到 SteamCMD 基线版本信息。"
        }
    }

    private func outputRequestsGuardCode(_ output: String) -> Bool {
        output.contains("steam guard")
        || output.contains("two-factor code")
        || output.contains("two factor code")
        || output.contains("access code")
        || output.contains("email code")
    }

    private func outputIndicatesLoginSuccess(_ output: String) -> Bool {
        output.contains("logged in ok")
        || output.contains("successfully logged in")
        || output.contains("waiting for user info...ok")
    }

    private func outputIndicatesAuthenticationFailure(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        return lowered.contains("invalid password")
            || lowered.contains("login failure")
            || lowered.contains("failed to log in")
            || lowered.contains("account logon denied")
            || lowered.contains("incorrect login")
            || lowered.contains("too many login failures")
            || lowered.contains("not logged on")
            || lowered.contains("logged in elsewhere")
            || lowered.contains("please use force_install_dir before logon")
            || lowered.contains("steam guard")
            || lowered.contains("access denied")
            || lowered.contains("this account")
    }

    private func loadCachedBrowserItemsIfPossible() {
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = loadBrowserCache(
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter
        ) {
            browserItems = cached.items
            browserState = .loaded
        }
    }

    private func mergeBrowserItems(_ items: [SteamWorkshopBrowserItem]) {
        guard !items.isEmpty else { return }
        var mergedByID = Dictionary(uniqueKeysWithValues: browserItems.map { ($0.id, $0) })
        for item in items {
            mergedByID[item.id] = item
        }
        browserItems = browserItems.map { mergedByID[$0.id] ?? $0 }

        let existingIDs = Set(browserItems.map(\.id))
        let appended = items.filter { !existingIDs.contains($0.id) }
        if !appended.isEmpty {
            browserItems.append(contentsOf: appended)
        }
    }

    private func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        } else {
            browserItems.append(item)
        }
    }

    private func needsDetailRefresh(for item: SteamWorkshopBrowserItem) -> Bool {
        item.detailFields.isEmpty
        || item.fileSizeText == nil
        || item.resolutionText == nil
        || item.workshopTypeText == nil
        || item.author == "未知作者"
        || item.authorProfileURL == nil
    }

    private func refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedBrowserItem else { return }
        if !forceRefresh && !needsDetailRefresh(for: item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedBrowserItem = true
        selectedBrowserItemError = nil

        let stub = SteamWorkshopBrowseStub(
            id: item.id,
            title: item.title,
            author: item.author,
            authorProfileURL: item.authorProfileURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            previewImageURL: item.previewImageURL
        )

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(stub: stub)
                let enriched = (try? await Self.enrichPreviewKind(for: refreshed)) ?? refreshed
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.selectedBrowserItem = enriched
                    self.mergeBrowserItem(enriched)
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = error.localizedDescription
                }
            }
        }
    }

    private func prefetchUpcomingBrowserPageIfNeeded(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) {
        guard page > 1 else { return }
        let key = "\(source.rawValue)|\(trendingWindow.rawValue)|\(themeFilter.rawValue)|\(ageRatingFilter.rawValue)|\(resolutionFilter.rawValue)|\(categoryFilter.rawValue)|\(query)|\(page)"
        guard prefetchedBrowserPageKeys.insert(key).inserted else { return }

        Task(priority: .utility) {
            guard let stubs = try? await Self.fetchWorkshopStubs(
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page
            ), !stubs.isEmpty else {
                return
            }
            _ = try? await Self.fetchWorkshopItems(stubs: stubs)
        }
    }

    private func loadBrowserCache(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter
    ) -> SteamWorkshopBrowserCacheSnapshot? {
        let url = cacheFileURL(
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter
        )
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamWorkshopBrowserCacheSnapshot.self, from: data)
    }

    private func saveBrowserCache(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        items: [SteamWorkshopBrowserItem]
    ) {
        let snapshot = SteamWorkshopBrowserCacheSnapshot(fetchedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? data.write(
            to: cacheFileURL(
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter
            ),
            options: [.atomic]
        )
    }

    private func cacheFileURL(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter
    ) -> URL {
        let normalized = query.isEmpty
            ? "all"
            : query.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let theme = themeFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let age = ageRatingFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let resolution = resolutionFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let category = categoryFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let period = source.supportsTimeRange ? trendingWindow.rawValue : "na"
        return cacheDirectoryURL.appendingPathComponent("\(source.rawValue)-\(period)-\(theme)-\(age)-\(resolution)-\(category)-\(normalized).json")
    }

    private static func detailCacheDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("ItemDetails", isDirectory: true)
    }

    private static func detailCacheFileURL(id: String) -> URL {
        detailCacheDirectoryURL().appendingPathComponent("\(id).json")
    }

    private static func loadDetailCache(id: String) -> SteamWorkshopBrowserItem? {
        let url = detailCacheFileURL(id: id)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDetailCacheSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.fetchedAt) < Constants.detailCacheTTL else {
            return nil
        }
        return snapshot.item
    }

    private static func saveDetailCache(item: SteamWorkshopBrowserItem) {
        let snapshot = SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: item)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = detailCacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: detailCacheFileURL(id: item.id), options: [.atomic])
    }

    private func buildInstalledRecord(at directory: URL) -> SteamWorkshopDownloadRecord? {
        let projectURL = directory.appendingPathComponent("project.json")
        let project = try? JSONDecoder().decode(SteamWorkshopProject.self, from: Data(contentsOf: projectURL))
        let previewURL = project?.preview.flatMap { preview in
            let url = directory.appendingPathComponent(preview)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let videoURL = resolveVideoURL(in: directory, preferredFileName: project?.file)
        let attributes = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        let updatedAt = attributes?.contentModificationDate ?? Date()
        let title = project?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = project?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = project?.tags ?? []
        let sizeText = videoURL.flatMap { fileSizeText(for: $0) } ?? "未知大小"
        let identifier = project?.workshopid ?? directory.lastPathComponent

        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : "Workshop #\(identifier)",
            description: description,
            tags: tags,
            folderURL: directory,
            previewURL: previewURL,
            videoURL: videoURL,
            updatedAt: updatedAt,
            sizeText: sizeText,
            status: .ready
        )
    }

    private func resolveVideoURL(in directory: URL, preferredFileName: String?) -> URL? {
        if let preferredFileName {
            let preferredURL = directory.appendingPathComponent(preferredFileName)
            if FileManager.default.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let supportedExtensions = Set(["mp4", "webm", "mov", "m4v"])
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return files.first {
            supportedExtensions.contains($0.pathExtension.localizedLowercase)
        }
    }

    private func fileSizeText(for url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
    }

    private func upsertTransientRecord(
        id: String,
        title: String,
        status: SteamWorkshopDownloadRecord.Status,
        sizeText: String? = nil
    ) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let previous = downloads[index]
            downloads[index] = SteamWorkshopDownloadRecord(
                id: id,
                title: previous.title,
                description: previous.description,
                tags: previous.tags,
                folderURL: previous.folderURL,
                previewURL: previous.previewURL,
                videoURL: previous.videoURL,
                updatedAt: Date(),
                sizeText: sizeText ?? previous.sizeText,
                status: status
            )
            return
        }

        let folderURL = libraryRootURL.appendingPathComponent(id, isDirectory: true)
        downloads.insert(
            SteamWorkshopDownloadRecord(
                id: id,
                title: title,
                description: "",
                tags: [],
                folderURL: folderURL,
                previewURL: nil,
                videoURL: nil,
                updatedAt: Date(),
                sizeText: sizeText ?? "等待下载",
                status: status
            ),
            at: 0
        )
    }

    private static func makeBrowseURL(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) -> URL {
        var components = URLComponents(string: Constants.steamCommunityBase)!
        var queryItems = [
            URLQueryItem(name: "appid", value: Constants.workshopAppID),
            URLQueryItem(name: "searchtext", value: query),
            URLQueryItem(name: "browsesort", value: source.browseFilter),
            URLQueryItem(name: "actualsort", value: source.browseFilter),
            URLQueryItem(name: "section", value: "readytouseitems"),
            URLQueryItem(name: "requiredtags[0]", value: "Video"),
            URLQueryItem(name: "numperpage", value: "\(Constants.browserPageSize)"),
            URLQueryItem(name: "p", value: "\(max(1, page))")
        ]
        if let themeTag = themeFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: themeTag))
        }
        if let ageTag = ageRatingFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: ageTag))
        }
        if let resolutionTag = resolutionFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: resolutionTag))
        }
        if let categoryTag = categoryFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: categoryTag))
        }
        if source.supportsTimeRange {
            queryItems.append(URLQueryItem(name: "days", value: trendingWindow.daysValue))
        }
        components.queryItems = queryItems
        return components.url!
    }

    private static func makeDetailURL(id: String) -> URL {
        var components = URLComponents(string: Constants.detailBase)!
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }

    private static func fetchWorkshopIDs(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) async throws -> [String] {
        let stubs = try await fetchWorkshopStubs(
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page
        )
        return stubs.map(\.id)
    }

    private static func fetchWorkshopStubs(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) async throws -> [SteamWorkshopBrowseStub] {
        let url = makeBrowseURL(
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page
        )
        let html = try await fetchHTML(url: url)
        let stubs = parseBrowsePage(html: html)
        if !stubs.isEmpty {
            return Array(stubs.prefix(Constants.browserPageSize))
        }

        let pattern = #"sharedfiles/filedetails/\?id=(\d+)"#
        let matches = firstCaptureMatches(pattern: pattern, in: html)
        var ordered: [SteamWorkshopBrowseStub] = []
        var seen = Set<String>()
        for id in matches where seen.insert(id).inserted {
            ordered.append(SteamWorkshopBrowseStub(id: id, title: nil, author: nil, authorProfileURL: nil, hasAdultContent: false, summary: nil, previewImageURL: nil))
        }
        return Array(ordered.prefix(Constants.browserPageSize))
    }

    private static func fetchWorkshopItems(stubs: [SteamWorkshopBrowseStub]) async throws -> [SteamWorkshopBrowserItem] {
        return try await withThrowingTaskGroup(of: (Int, SteamWorkshopBrowserItem?).self) { group in
            for (index, stub) in stubs.enumerated() {
                group.addTask {
                    do {
                        let item = try await fetchWorkshopItem(stub: stub)
                        return (index, try await enrichPreviewKind(for: item))
                    } catch {
                        let nsError = error as NSError
                        if nsError.domain == "SteamWorkshop", nsError.code == 13 {
                            return (index, nil)
                        }
                        let fallback = await fallbackBrowserItem(from: stub)
                        return (index, try? await enrichPreviewKind(for: fallback))
                    }
                }
            }

            var results = Array<SteamWorkshopBrowserItem?>(repeating: nil, count: stubs.count)
            for try await (index, item) in group {
                results[index] = item
            }
            return results.compactMap { $0 }
        }
    }

    private static func fetchWorkshopItem(stub: SteamWorkshopBrowseStub) async throws -> SteamWorkshopBrowserItem {
        if let cached = loadDetailCache(id: stub.id) {
            return mergeStub(stub, into: cached)
        }

        let detailURL = makeDetailURL(id: stub.id)
        let html = try await fetchHTML(url: detailURL)
        let parsed = parseDetailPage(html: html, fallbackID: stub.id)
        if let workshopTypeText = parsed.workshopTypeText,
           !workshopTypeText.localizedCaseInsensitiveContains("video") {
            throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "当前条目详情页标记类型为 \(workshopTypeText)，不是视频壁纸。"
            ])
        }
        let item = SteamWorkshopBrowserItem(
            id: stub.id,
            title: parsed.title,
            author: parsed.author,
            authorProfileURL: parsed.authorProfileURL ?? stub.authorProfileURL,
            hasAdultContent: stub.hasAdultContent,
            summary: parsed.summary,
            descriptionText: parsed.descriptionText,
            tags: parsed.tags,
            workshopTypeText: parsed.workshopTypeText,
            ageRatingText: parsed.ageRatingText,
            genreText: parsed.genreText,
            categoryText: parsed.categoryText,
            previewImageURL: parsed.previewImageURL,
            previewVideoURL: parsed.previewVideoURL,
            previewAssetKind: parsed.previewVideoURL == nil ? .unknown : .video,
            fileSizeText: parsed.fileSizeText,
            resolutionText: parsed.resolutionText,
            postedText: parsed.postedText,
            updatedText: parsed.updatedText,
            favoritesText: parsed.favoritesText,
            subscriptionsText: parsed.subscriptionsText,
            scoreText: parsed.scoreText,
            detailFields: parsed.detailFields,
            detailURL: detailURL
        )
        saveDetailCache(item: item)
        return mergeStub(stub, into: item)
    }

    private static func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw URLError(.cannotDecodeRawData)
        }
        return html
    }

    private static func parseDetailPage(html: String, fallbackID: String) -> SteamWorkshopDetailParseResult {
        let title = firstCapture(
            pattern: #"<div[^>]*class="workshopItemTitle"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        ?? metaContent(property: "og:title", in: html)
        ?? "Workshop #\(fallbackID)"

        let author = firstCapture(
            pattern: #"<div[^>]*class="friendBlockContent"[^>]*>\s*(.*?)\s*<br"#,
            in: html
        ) ?? "未知作者"
        let authorProfileURL = normalizeSteamCommunityURL(
            firstCapture(
                pattern: #"<a[^>]*class="friendBlockLinkOverlay"[^>]*href="([^"]+)""#,
                in: html
            )
        )

        let summary = metaContent(property: "og:description", in: html)
            ?? firstCapture(pattern: #"<div[^>]*class="workshopItemDescription"[^>]*>(.*?)</div>"#, in: html)
            ?? ""

        let descriptionText = firstCapture(
            pattern: #"<div[^>]*class="workshopItemDescription"[^>]*>(.*?)</div>"#,
            in: html
        ) ?? summary

        let stats = parseStatsMap(from: html)
        let workshopTags = parseWorkshopTags(from: html)
        let rawTags = workshopTags.flatMap(\.values)
        let tags = Array(NSOrderedSet(array: rawTags.filter { !$0.isEmpty })) as? [String] ?? []
        let detailFields = buildDetailFields(stats: stats, workshopTags: workshopTags)
        let previewImageURL = metaURL(property: "og:image", in: html)
        let previewVideoURL = firstURLMatch(
            pattern: #"https:[^"'\\]+?\.(?:mp4|webm)(?:\?[^"'\\<]*)?"#,
            in: html
        )

        return SteamWorkshopDetailParseResult(
            title: normalizeText(title),
            author: normalizeAuthorName(author),
            authorProfileURL: authorProfileURL,
            summary: normalizeText(summary),
            descriptionText: normalizeText(descriptionText),
            tags: tags.map(normalizeText),
            workshopTypeText: normalizedWorkshopTagValue(forKey: "Type", in: workshopTags)
                ?? normalizedStatValue(forKey: "Type", in: stats),
            ageRatingText: normalizedWorkshopTagValue(forKey: "Age Rating", in: workshopTags),
            genreText: normalizedWorkshopTagValue(forKey: "Genre", in: workshopTags),
            categoryText: normalizedWorkshopTagValue(forKey: "Category", in: workshopTags),
            previewImageURL: previewImageURL,
            previewVideoURL: previewVideoURL,
            fileSizeText: normalizedStatValue(forKey: "File Size", in: stats)
                ?? normalizedStatValue(forKey: "文件大小", in: stats),
            resolutionText: normalizedWorkshopTagValue(forKey: "Resolution", in: workshopTags)
                ?? normalizedStatValue(forKey: "Resolution", in: stats)
                ?? resolutionFallback(in: html),
            postedText: normalizedStatValue(forKey: "Posted", in: stats)
                ?? normalizedStatValue(forKey: "发表于", in: stats),
            updatedText: normalizedStatValue(forKey: "Updated", in: stats)
                ?? normalizedStatValue(forKey: "Last Updated", in: stats)
                ?? normalizedStatValue(forKey: "更新于", in: stats),
            favoritesText: normalizedStatValue(forKey: "Favorite", in: stats)
                ?? normalizedStatValue(forKey: "Favorited", in: stats),
            subscriptionsText: normalizedStatValue(forKey: "Subscriptions", in: stats),
            scoreText: normalizedStatValue(forKey: "Score", in: stats),
            detailFields: detailFields
        )
    }

    private static func parseStatsMap(from html: String) -> [String: String] {
        let labels = firstCaptureMatches(
            pattern: #"<div[^>]*class="detailsStatLeft"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        let values = firstCaptureMatches(
            pattern: #"<div[^>]*class="detailsStatRight"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        var map: [String: String] = [:]
        for index in 0..<min(labels.count, values.count) {
            let key = normalizeText(labels[index])
            let value = normalizeText(values[index])
            if !key.isEmpty, !value.isEmpty {
                map[key] = value
            }
        }
        return map
    }

    private static func normalizedStatValue(forKey key: String, in stats: [String: String]) -> String? {
        if let direct = stats[key], !direct.isEmpty {
            return direct
        }
        return stats.first { candidate, _ in
            candidate.localizedCaseInsensitiveContains(key)
        }?.value
    }

    private static func parseWorkshopTags(from html: String) -> [(key: String, values: [String])] {
        let pattern = #"<div[^>]*class="workshopTags"[^>]*>\s*<span[^>]*class="workshopTagsTitle"[^>]*>(.*?)</span>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [(key: String, values: [String])] = []

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: html),
                  let valuesRange = Range(match.range(at: 2), in: html) else { continue }

            let key = normalizeText(String(html[keyRange]).replacingOccurrences(of: ":", with: ""))
            let valuesHTML = String(html[valuesRange])
            let values = firstCaptureMatches(
                pattern: #"<a[^>]*>\s*(.*?)\s*</a>"#,
                in: valuesHTML
            ).map(normalizeText).filter { !$0.isEmpty }

            if !key.isEmpty, !values.isEmpty {
                result.append((key: key, values: values))
            }
        }

        return result
    }

    private static func normalizedWorkshopTagValue(
        forKey key: String,
        in workshopTags: [(key: String, values: [String])]
    ) -> String? {
        if let exact = workshopTags.first(where: { $0.key.compare(key, options: .caseInsensitive) == .orderedSame }) {
            return exact.values.joined(separator: " · ")
        }
        if let fuzzy = workshopTags.first(where: { $0.key.localizedCaseInsensitiveContains(key) }) {
            return fuzzy.values.joined(separator: " · ")
        }
        return nil
    }

    private static func buildDetailFields(
        stats: [String: String],
        workshopTags: [(key: String, values: [String])]
    ) -> [SteamWorkshopDetailField] {
        var fields: [SteamWorkshopDetailField] = []
        var seen = Set<String>()

        func appendField(label: String, value: String) {
            let normalizedLabel = normalizeText(label.replacingOccurrences(of: ":", with: ""))
            let normalizedValue = normalizeText(value)
            guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else { return }
            let key = "\(normalizedLabel)|\(normalizedValue)"
            guard seen.insert(key).inserted else { return }
            fields.append(SteamWorkshopDetailField(label: normalizedLabel, value: normalizedValue))
        }

        let preferredStatOrder = [
            "File Size", "文件大小",
            "Posted", "发表于",
            "Updated", "Last Updated",
            "Subscriptions", "Favorited", "Favorites", "Favorite", "Score"
        ]
        for key in preferredStatOrder {
            if let value = normalizedStatValue(forKey: key, in: stats) {
                appendField(label: key, value: value)
            }
        }

        for tag in workshopTags {
            appendField(label: tag.key, value: tag.values.joined(separator: " · "))
        }

        for (key, value) in stats.sorted(by: { $0.key < $1.key }) {
            appendField(label: key, value: value)
        }

        return fields
    }

    private static func resolutionFallback(in html: String) -> String? {
        guard let match = firstCapture(
            pattern: #"(\d{3,5}\s*[xX×]\s*\d{3,5})"#,
            in: html
        ) else {
            return nil
        }
        return normalizeText(match.replacingOccurrences(of: "x", with: "×"))
    }

    private static func metaContent(property: String, in html: String) -> String? {
        firstCapture(
            pattern: #"<meta[^>]+property="\#(property)"[^>]+content="([^"]+)""#,
            in: html
        )
    }

    private static func metaURL(property: String, in html: String) -> URL? {
        guard let value = metaContent(property: property, in: html) else { return nil }
        return URL(string: htmlDecode(value))
    }

    private static func firstURLMatch(pattern: String, in html: String) -> URL? {
        guard let value = firstCapture(pattern: pattern, in: html) else { return nil }
        return URL(string: htmlDecode(value))
    }

    private static func normalizeSteamCommunityURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let decoded = htmlDecode(rawValue)
        if decoded.hasPrefix("//") {
            return URL(string: "https:\(decoded)")
        }
        if decoded.hasPrefix("/") {
            return URL(string: decoded, relativeTo: URL(string: "https://steamcommunity.com"))?.absoluteURL
        }
        return URL(string: decoded)
    }

    private static func parseBrowsePage(html: String) -> [SteamWorkshopBrowseStub] {
        var results: [SteamWorkshopBrowseStub] = []
        var seen = Set<String>()
        let browseSummaries = parseBrowseSummaries(from: html)

        let blockPattern = #"<div[^>]*class="workshopItem"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 2,
                  let blockRange = Range(match.range(at: 1), in: html) else { continue }

            let block = String(html[blockRange])
            let id = firstCapture(
                pattern: #"data-publishedfileid="(\d+)""#,
                in: block
            ).map(normalizeText) ?? ""
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            let title = firstCapture(
                pattern: #"<div[^>]*class="workshopItemTitle[^"]*"[^>]*>\s*(.*?)\s*</div>"#,
                in: block
            )

            let author = firstCapture(
                pattern: #"<div[^>]*class="workshopItemAuthorName[^"]*"[^>]*>.*?<a[^>]*>\s*(.*?)\s*</a>"#,
                in: block
            )

            let previewImageURL = firstURLMatch(
                pattern: #"<img[^>]*class="workshopItemPreviewImage[^"]*"[^>]*src="([^"]+)""#,
                in: block
            )

            results.append(
                SteamWorkshopBrowseStub(
                    id: id,
                    title: title.map(normalizeText),
                    author: author.map(normalizeAuthorName),
                    authorProfileURL: nil,
                    hasAdultContent: block.localizedCaseInsensitiveContains("has_adult_content"),
                    summary: browseSummaries[id].map(normalizeText),
                    previewImageURL: previewImageURL
                )
            )
        }

        return results
    }

    private static func parseBrowseSummaries(from html: String) -> [String: String] {
        let pattern = #"SharedFileBindMouseHover\(\s*"sharedfile_(\d+)"\s*,\s*false\s*,\s*(\{.*?\})\s*\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [String: String] = [:]
        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let payloadRange = Range(match.range(at: 2), in: html) else { continue }

            let id = String(html[idRange])
            let payload = String(html[payloadRange])
                .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let description = (json["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shortDescription = (json["short_description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = description?.isEmpty == false ? description : shortDescription
            if let value, !value.isEmpty {
                result[id] = value
            }
        }
        return result
    }

    private static func enrichPreviewKind(for item: SteamWorkshopBrowserItem) async throws -> SteamWorkshopBrowserItem {
        if item.previewVideoURL != nil {
            return withPreviewKind(.video, item: item)
        }
        guard let previewImageURL = item.previewImageURL else {
            return item
        }

        let mimeType = try? await fetchPreviewMimeType(url: previewImageURL)
        let previewKind: SteamWorkshopPreviewAssetKind
        switch mimeType?.lowercased() {
        case let value? where value.contains("gif"):
            previewKind = .animatedImage
        case let value? where value.contains("image/"):
            previewKind = .stillImage
        default:
            previewKind = .unknown
        }
        return withPreviewKind(previewKind, item: item)
    }

    private static func fetchPreviewMimeType(url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return http.value(forHTTPHeaderField: "Content-Type")
    }

    private static func withPreviewKind(_ previewKind: SteamWorkshopPreviewAssetKind, item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title,
            author: item.author,
            authorProfileURL: item.authorProfileURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            descriptionText: item.descriptionText,
            tags: item.tags,
            workshopTypeText: item.workshopTypeText,
            ageRatingText: item.ageRatingText,
            genreText: item.genreText,
            categoryText: item.categoryText,
            previewImageURL: item.previewImageURL,
            previewVideoURL: item.previewVideoURL,
            previewAssetKind: previewKind,
            fileSizeText: item.fileSizeText,
            resolutionText: item.resolutionText,
            postedText: item.postedText,
            updatedText: item.updatedText,
            favoritesText: item.favoritesText,
            subscriptionsText: item.subscriptionsText,
            scoreText: item.scoreText,
            detailFields: item.detailFields,
            detailURL: item.detailURL
        )
    }

    private static func fallbackBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: stub.id,
            title: normalizedStubTitle(stub),
            author: normalizedStubAuthor(stub),
            authorProfileURL: stub.authorProfileURL,
            hasAdultContent: stub.hasAdultContent,
            summary: stub.summary ?? "",
            descriptionText: stub.summary ?? "",
            tags: [],
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            previewImageURL: stub.previewImageURL,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: nil,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            detailFields: [],
            detailURL: makeDetailURL(id: stub.id)
        )
    }

    private static func mergeStub(_ stub: SteamWorkshopBrowseStub, into item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title.isEmpty ? normalizedStubTitle(stub) : item.title,
            author: item.author.isEmpty ? normalizedStubAuthor(stub) : item.author,
            authorProfileURL: item.authorProfileURL ?? stub.authorProfileURL,
            hasAdultContent: item.hasAdultContent || stub.hasAdultContent,
            summary: item.summary,
            descriptionText: item.descriptionText,
            tags: item.tags,
            workshopTypeText: item.workshopTypeText,
            ageRatingText: item.ageRatingText,
            genreText: item.genreText,
            categoryText: item.categoryText,
            previewImageURL: item.previewImageURL ?? stub.previewImageURL,
            previewVideoURL: item.previewVideoURL,
            previewAssetKind: item.previewAssetKind,
            fileSizeText: item.fileSizeText,
            resolutionText: item.resolutionText,
            postedText: item.postedText,
            updatedText: item.updatedText,
            favoritesText: item.favoritesText,
            subscriptionsText: item.subscriptionsText,
            scoreText: item.scoreText,
            detailFields: item.detailFields,
            detailURL: item.detailURL
        )
    }

    private static func normalizedStubTitle(_ stub: SteamWorkshopBrowseStub) -> String {
        let title = stub.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Workshop #\(stub.id)" : title
    }

    private static func normalizedStubAuthor(_ stub: SteamWorkshopBrowseStub) -> String {
        let author = normalizeAuthorName(stub.author ?? "")
        return author.isEmpty ? "未知作者" : author
    }

    private static func normalizeAuthorName(_ text: String) -> String {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return "" }
        let statusTokens = ["在线", "离线", "游戏中", "正在游戏", "当前离线"]
        for token in statusTokens {
            if let range = normalized.range(of: token) {
                return String(normalized[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return normalized
    }

    private static func firstCapture(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard let swiftRange = Range(targetRange, in: html) else { return nil }
        return String(html[swiftRange])
    }

    private static func firstCaptureMatches(pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let swiftRange = Range(targetRange, in: html) else { return nil }
            return normalizeText(String(html[swiftRange]))
        }
    }

    private static func normalizeText(_ text: String) -> String {
        let noBreaks = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        let withoutTags = noBreaks.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = htmlDecode(withoutTags)
        let compacted = decoded.replacingOccurrences(
            of: #"[ \t\r\f\v]+"#,
            with: " ",
            options: .regularExpression
        )
        return compacted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlDecode(_ text: String) -> String {
        var decoded = text
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#x2F;": "/"
        ]
        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }

    private static func fileSizeText(forBytes bytes: Int64) -> String {
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

    private static func parseByteCount(from text: String?) -> Int64? {
        guard let text else { return nil }
        let normalized = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard let value = Double(firstCapture(pattern: #"([0-9]+(?:\.[0-9]+)?)"#, in: normalized) ?? "") else {
            return nil
        }

        if normalized.contains("GB") {
            return Int64(value * 1024 * 1024 * 1024)
        }
        if normalized.contains("MB") {
            return Int64(value * 1024 * 1024)
        }
        if normalized.contains("KB") {
            return Int64(value * 1024)
        }
        if normalized.contains("B") {
            return Int64(value)
        }
        return nil
    }
}
