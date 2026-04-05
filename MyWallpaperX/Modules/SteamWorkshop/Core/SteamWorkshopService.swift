//
//  SteamWorkshopService.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Combine
import Darwin
@MainActor
final class SteamWorkshopService: ObservableObject {
    static let shared = SteamWorkshopService()
    static let authorNameStore = SteamWorkshopAuthorNameStore()

    enum Constants {
        static let workshopAppID = "431960"
        static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        static let publishedFileDetailsAPI = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
        static let authorWorkshopPageSize = 30
        static let detailHydrationBatchSize = 4
        static let detailHydrationInterBatchDelayNanoseconds: UInt64 = 1_300_000_000
        static let detailPrefetchBatchSize = 2
        static let detailPrefetchInterBatchDelayNanoseconds: UInt64 = 2_000_000_000
        static let browserInteractionDeferralInterval: TimeInterval = 1.2
        static let detailRequestDeferralInterval: TimeInterval = 4.0
        static let bundledSteamBundleName = "SteamCMDRuntime.bundle"
        static let bundledSteamRootName = "Steam"
        static let bundledSteamMetadataName = "runtime-metadata.json"
        static let browserPageSize = 24
        static let cacheTTL: TimeInterval = 60 * 15
        static let detailCacheTTL: TimeInterval = 60 * 60 * 24
        static let defaultsLastUsername = "SteamWorkshop.lastUsername"
        static let defaultsLastAuthenticatedAt = "SteamWorkshop.lastAuthenticatedAt"
        static let authProbeCacheTTL: TimeInterval = 60 * 15
        static let authProbeTimeout: TimeInterval = 20
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

    @Published private(set) var browserItems: [SteamWorkshopBrowserItem] = [] {
        didSet { updateDisplayedBrowserItems() }
    }
    @Published private(set) var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    @Published private(set) var pendingBrowserScrollRestoreOffset: CGFloat?
    @Published private(set) var browserState: SteamWorkshopBrowserLoadState = .idle
    @Published private(set) var isRefreshingBrowserFeed = false
    @Published private(set) var previewReloadToken: Int = 0
    @Published private(set) var isLoadingMoreBrowserItems = false
    @Published private(set) var hasMoreBrowserItems = true
    @Published var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var source: SteamWorkshopSource = .featured {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var browserQuery: String = "" {
        didSet {
            guard !isUpdatingBrowserQueryProgrammatically else { return }
            handleBrowserQueryChanged()
        }
    }
    @Published var trendingWindow: SteamWorkshopTrendingWindow = .week {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var themeFilter: SteamWorkshopThemeFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var ageRatingFilter: SteamWorkshopAgeRatingFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var resolutionFilter: SteamWorkshopResolutionFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var categoryFilter: SteamWorkshopCategoryFilter = .all {
        didSet { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    }
    @Published var downloadsQuery: String = ""
    @Published var downloadsSortMode: SteamWorkshopDownloadsSortMode = .updatedAt
    @Published var downloadsSortAscending: Bool = false
    @Published var zoomOffset: Int = 0
    @Published var statusMessage: String = "浏览页使用原生网格展示，后台抓取 Wallpaper Engine 创意工坊视频信息。"
    @Published var currentWorkshopItemID: String?
    @Published var currentPageTitle: String = "Steam 创意工坊"
    @Published private(set) var browserSectionTitle: String = "Steam 创意工坊"
    @Published private(set) var isBrowsingAuthorWorkshop = false
    @Published private(set) var activeAuthorWorkshopName: String?
    @Published var requestedURL: URL
    @Published var navigationVersion: Int = 0
    @Published var activeDownloadItemID: String?
    @Published var isDownloadsMultiSelectMode = false
    @Published var selectedDownloadID: String?
    @Published var selectedDownloadIDs: Set<String> = []
    @Published var downloadError: String?
    @Published var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    @Published var selectedDownloadDetailItem: SteamWorkshopBrowserItem?
    @Published var selectedBrowserItem: SteamWorkshopBrowserItem?
    @Published var isRefreshingSelectedDownloadDetailItem = false
    @Published private(set) var isRefreshingSelectedBrowserItem = false
    @Published var selectedDownloadDetailError: String?
    @Published var selectedBrowserItemError: String?
    @Published var requiresLogin: Bool = true
    @Published var isAnonymousBrowsing = false
    @Published var authPhase: SteamWorkshopAuthenticationPhase = .credentials
    @Published var isLoginSheetPresented = false
    @Published var isAuthenticating = false
    @Published var isPreparingRuntime = false
    @Published var authStatusMessage: String = "首次进入请登录 Steam，软件会使用随 App 打包的 SteamCMD 并保留登录态。"
    @Published var authError: String?
    @Published var authSessionState: SteamWorkshopAuthSessionState = .unknown
    @Published var steamRuntimeVersion: String = "未检测"
    @Published var steamRuntimeUpdateStatus: String = "当前使用 App 内置 SteamCMD 基线版本。"
    @Published var steamUsername: String = ""
    @Published var steamPassword: String = ""
    @Published var steamGuardCode: String = ""

    private var browserFetchTask: Task<Void, Never>?
    private var browserDetailHydrationTask: Task<Void, Never>?
    private var browserNextPage = 1
    private var prefetchedBrowserPageKeys = Set<String>()
    private var prefetchedBrowserPages: [String: SteamWorkshopBrowseStubPage] = [:]
    private var pendingBrowserDetailStubs: [SteamWorkshopBrowseStub] = []
    private var pendingBrowserDetailStubIDs = Set<String>()
    private var browserDetailRetryCounts: [String: Int] = [:]
    private var prioritizedVisibleBrowserItemIDs: [String] = []
    private var lastPreviewPrefetchIDs: [String] = []
    private var backgroundDetailDeferralUntil: Date = .distantPast
    let defaults = UserDefaults.standard
    var loginProcess: Process?
    var loginInputHandle: FileHandle?
    var loginOutputHandle: FileHandle?
    var loginOutputBuffer: String = ""
    var loginPasswordSent = false
    var loginSucceeded = false
    var pendingLoginUsername: String = ""
    var pendingLoginPassword: String = ""
    var pendingLoginCommand: String?
    private var startupTask: Task<Void, Never>?
    var loginBootstrapTimeoutTask: Task<Void, Never>?
    var loginSessionID: String = ""
    var pendingDownloadRequest: SteamWorkshopPendingDownloadRequest?
    var queuedDownloadRequests: [SteamWorkshopPendingDownloadRequest] = []
    var lastSuccessfulSessionValidationAt: Date?
    var activeDownloadProcess: Process?
    var activeDownloadTask: Task<Void, Never>?
    var activeDownloadWasCancelled = false
    var selectedItemDetailTask: Task<Void, Never>?
    private var discoveryBrowseSnapshot: SteamWorkshopDiscoveryBrowseSnapshot?
    private var currentBrowserScrollOffsetY: CGFloat = 0
    private var savedDiscoveryQueryBeforeAuthorBrowse: String?
    private var isUpdatingBrowserQueryProgrammatically = false
    private var suppressAutomaticBrowseNavigation = false
    private var browseContext: SteamWorkshopBrowseContext = .discovery {
        didSet {
            browserSectionTitle = browseContext.title
            isBrowsingAuthorWorkshop = browseContext.isAuthorWorkshop
            if case let .authorWorkshop(authorName, _) = browseContext {
                activeAuthorWorkshopName = authorName
            } else {
                activeAuthorWorkshopName = nil
            }
            updateDisplayedBrowserItems()
            NotificationCenter.default.post(
                name: .steamWorkshopBrowseContextDidChange,
                object: nil,
                userInfo: [
                    "isAuthorWorkshop": browseContext.isAuthorWorkshop,
                    "title": browseContext.title
                ]
            )
        }
    }

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

    var exportedVideosRootURL: URL { libraryRootURL }

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
        let filtered: [SteamWorkshopDownloadRecord]
        if query.isEmpty {
            filtered = downloads
        } else {
            let normalized = query.localizedLowercase
            filtered = downloads.filter {
                $0.title.localizedLowercase.contains(normalized)
                || $0.description.localizedLowercase.contains(normalized)
                || $0.tags.contains(where: { $0.localizedLowercase.contains(normalized) })
                || $0.id.localizedLowercase.contains(normalized)
                || $0.browserItem?.author.localizedLowercase.contains(normalized) == true
            }
        }
        return filtered.sorted { lhs, rhs in
            switch downloadsSortMode {
            case .updatedAt:
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison == .orderedSame {
                    return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
                }
                return downloadsSortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
            case .size:
                let lhsSize = Self.parseByteCount(from: lhs.sizeText) ?? 0
                let rhsSize = Self.parseByteCount(from: rhs.sizeText) ?? 0
                if lhsSize == rhsSize {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return downloadsSortAscending ? (lhsSize < rhsSize) : (lhsSize > rhsSize)
            }
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

    var activeBrowserContextSummary: String? {
        guard let activeAuthorWorkshopName else { return nil }
        return "当前正在浏览 \(activeAuthorWorkshopName) 的创意工坊作品"
    }

    var hasVisibleBrowserItems: Bool {
        !displayedBrowserItems.isEmpty
    }

    func isDownloading(itemID: String) -> Bool {
        latestDownloadRecord(for: itemID)?.status == .downloading
    }

    func isQueuedForDownload(itemID: String) -> Bool {
        latestDownloadRecord(for: itemID)?.status == .queued
    }

    func latestDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        downloads.first(where: { $0.id == itemID })
    }

    var selectedDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let selectedDownloadID else { return nil }
        return latestDownloadRecord(for: selectedDownloadID)
    }

    var effectiveSelectedDownloadIDs: Set<String> {
        if isDownloadsMultiSelectMode {
            return selectedDownloadIDs
        }
        if let selectedDownloadID {
            return [selectedDownloadID]
        }
        return []
    }

    var canDeleteSelectedDownload: Bool {
        let selectedIDs = effectiveSelectedDownloadIDs
        guard !selectedIDs.isEmpty else { return false }
        return selectedIDs.allSatisfy { id in
            guard let record = latestDownloadRecord(for: id) else { return false }
            switch record.status {
            case .ready, .failed:
                return true
            case .queued, .downloading:
                return false
            }
        }
    }

    var canShowSelectedDownloadInfo: Bool {
        !isDownloadsMultiSelectMode && selectedDownloadRecord != nil
    }

    var canRevealSelectedDownload: Bool {
        !isDownloadsMultiSelectMode && selectedDownloadRecord != nil
    }

    var canSelectAllDownloads: Bool {
        isDownloadsMultiSelectMode && !filteredDownloads.isEmpty
    }

    func downloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              record.status == .ready else {
            return nil
        }
        return record
    }

    func playableDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              record.status == .ready,
              record.isPlayable else {
            return nil
        }
        return record
    }

    func isDownloaded(itemID: String) -> Bool {
        playableDownloadRecord(for: itemID) != nil
    }

    func latestDownloadFailure(for itemID: String) -> String? {
        latestDownloadRecord(for: itemID)?.failureMessage
    }

    func updateBrowserScrollMetrics(
        offsetY: CGFloat,
        contentHeight _: CGFloat,
        viewportHeight _: CGFloat
    ) {
        currentBrowserScrollOffsetY = offsetY
    }

    func prioritizeVisibleBrowserItemIDs(_ ids: [String]) {
        let normalized = Array(NSOrderedSet(array: ids.filter { !$0.isEmpty })) as? [String] ?? []
        guard normalized != prioritizedVisibleBrowserItemIDs else { return }
        prioritizedVisibleBrowserItemIDs = normalized
        noteUserBrowsingActivity()
        prefetchBrowserPreviewImages(aroundVisibleIDs: normalized)
        guard !normalized.isEmpty, pendingBrowserDetailStubs.count > 1 else { return }

        let prioritizedSet = Set(normalized)
        let front = pendingBrowserDetailStubs.filter { prioritizedSet.contains($0.id) }
        guard !front.isEmpty else { return }
        let back = pendingBrowserDetailStubs.filter { !prioritizedSet.contains($0.id) }
        pendingBrowserDetailStubs = front.sorted { lhs, rhs in
            (normalized.firstIndex(of: lhs.id) ?? .max) < (normalized.firstIndex(of: rhs.id) ?? .max)
        } + back
    }

    func consumePendingBrowserScrollRestoreOffset() {
        pendingBrowserScrollRestoreOffset = nil
    }

    func navigateToBrowse() {
        cancelBrowserDetailHydration()
        requestedURL = requestedURLForCurrentContext(page: 1)
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = browseContext.title
        fetchBrowserItems()
    }

    func refresh() {
        cancelBrowserDetailHydration()
        navigationVersion += 1
        reloadInstalledItems()
        SteamWorkshopPreviewRequestCoordinator.shared.resetAllFailureStates()
        previewReloadToken += 1
        isRefreshingBrowserFeed = true
        statusMessage = browseContext.isAuthorWorkshop
            ? "正在刷新作者工坊列表…"
            : "正在刷新 Steam 创意工坊列表…"
        fetchBrowserItems(forceRefresh: true)
    }

    func loadMoreBrowserItemsIfNeeded() {
        guard !isLoadingMoreBrowserItems, hasMoreBrowserItems, browserState == .loaded else { return }

        let browseContext = self.browseContext
        let source = self.source
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter
        let page = browserNextPage
        let expectedNavigationVersion = navigationVersion
        let prefetchKey = browserPagePrefetchKey(
            context: browseContext,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page
        )

        logBrowserDebug(
            "loadMore start context=\(browseContext.title) page=\(page) query=\(query) currentCount=\(browserItems.count) hasMore=\(hasMoreBrowserItems)"
        )
        isLoadingMoreBrowserItems = true

        Task(priority: .userInitiated) { [weak self] in
            do {
                let pageResult: SteamWorkshopBrowseStubPage
                if let prefetched = await MainActor.run(body: { self?.prefetchedBrowserPages.removeValue(forKey: prefetchKey) }) {
                    pageResult = prefetched
                } else {
                    pageResult = try await Self.fetchWorkshopStubPage(
                        context: browseContext,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: page
                    )
                }
                let stubs = pageResult.stubs
                let seededItems = stubs.map(Self.seededBrowserItem)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.navigationVersion == expectedNavigationVersion, self.browseContext == browseContext else { return }
                    let existingIDs = Set(self.browserItems.map(\.id))
                    let fallbackItems = seededItems
                        .filter { !existingIDs.contains($0.id) }
                    self.browserItems.append(contentsOf: fallbackItems)
                    self.prefetchBrowserPreviewImages(for: fallbackItems, limit: 36)
                    self.browserNextPage = page + 1
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.isLoadingMoreBrowserItems = false
                    self.statusMessage = self.prefetchStatusMessage(for: browseContext, page: page)
                    self.enqueueBrowserDetailHydration(
                        stubs: stubs,
                        context: browseContext,
                        navigationVersion: expectedNavigationVersion,
                        resetQueue: false
                    )
                }
                await MainActor.run {
                    guard let self else { return }
                    guard self.navigationVersion == expectedNavigationVersion, self.browseContext == browseContext else { return }
                    self.statusMessage = self.baseCardsStatusMessage(for: browseContext, count: self.browserItems.count)
                    self.logBrowserDebug(
                        "loadMore enqueued context=\(browseContext.title) page=\(page) stubCount=\(stubs.count) total=\(self.browserItems.count) nextPage=\(self.browserNextPage) hasMore=\(self.hasMoreBrowserItems)"
                    )
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        context: browseContext,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage,
                        lookaheadDepth: 1
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    guard self.navigationVersion == expectedNavigationVersion, self.browseContext == browseContext else { return }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = false
                    self.logBrowserDebug(
                        "loadMore failed context=\(browseContext.title) page=\(page) error=\(error.localizedDescription)"
                    )
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
            await MainActor.run {
                guard !self.isLoadingMoreBrowserItems else { return }
                guard self.browserFetchTask == nil else { return }
                if self.browserItems.isEmpty || self.browserState == .idle {
                    self.logBrowserDebug(
                        "prepareForBrowserEntry trigger initial fetch context=\(self.browseContext.title) state=\(self.browserState)"
                    )
                    self.fetchBrowserItems(forceRefresh: true)
                }
            }
        }
    }

    func presentItemDetail(_ item: SteamWorkshopBrowserItem) {
        prioritizeUserRequestedDetail()
        let resolvedItem = browserItems.first(where: { $0.id == item.id }) ?? item
        selectedBrowserItem = resolvedItem
        selectedBrowserItemError = nil
        currentWorkshopItemID = resolvedItem.id
        currentPageTitle = resolvedItem.title
        statusMessage = "已加载 \(resolvedItem.title)"
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: needsDetailRefresh(for: resolvedItem))
    }

    func dismissItemDetail() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
    }

    func retrySelectedBrowserItemDetailRefresh() {
        retrySelectedBrowserPreviewLoad()
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
    }

    private func retrySelectedBrowserPreviewLoad() {
        guard let item = selectedBrowserItem else { return }
        if let previewURL = item.previewImageURL {
            SteamWorkshopPreviewRequestCoordinator.shared.resetFailureState(for: previewURL)
            let cacheKey = steamWorkshopPreviewCacheKey(for: previewURL)
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
        }
        previewReloadToken += 1
    }

    func showAuthorWorkshop(for item: SteamWorkshopBrowserItem) {
        guard let workshopURL = Self.resolvedAuthorWorkshopURL(for: item) else { return }
        dismissItemDetail()
        if !browseContext.isAuthorWorkshop {
            discoveryBrowseSnapshot = makeDiscoveryBrowseSnapshot()
        }
        savedDiscoveryQueryBeforeAuthorBrowse = browseContext.isAuthorWorkshop ? savedDiscoveryQueryBeforeAuthorBrowse : browserQuery
        browseContext = .authorWorkshop(
            authorName: item.author.isEmpty ? "未知作者" : item.author,
            workshopURL: workshopURL
        )
        setBrowserQuery("")
        requestedURL = requestedURLForCurrentContext(page: 1)
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = browseContext.title
        statusMessage = loadingStatusMessage(for: browseContext)
        fetchBrowserItems()
    }

    func returnToDiscoveryBrowse() {
        guard browseContext.isAuthorWorkshop else { return }
        browserFetchTask?.cancel()
        browserFetchTask = nil
        cancelBrowserDetailHydration()
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        navigationVersion += 1
        let restoredQuery = savedDiscoveryQueryBeforeAuthorBrowse ?? ""
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        browseContext = .discovery
        if let snapshot = discoveryBrowseSnapshot {
            restoreDiscoveryBrowseSnapshot(snapshot, restoredQuery: restoredQuery)
        } else {
            setBrowserQuery(restoredQuery)
            navigateToBrowse()
        }
        discoveryBrowseSnapshot = nil
    }

    private func requestedURLForCurrentContext(page: Int) -> URL {
        switch browseContext {
        case .discovery:
            return Self.makeBrowseURL(
                source: source,
                query: browserQuery,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page
            )
        case .authorWorkshop(_, let workshopURL):
            return Self.makeAuthorWorkshopURL(baseURL: workshopURL, page: page)
        }
    }

    private func handleBrowserQueryChanged() {
        if browseContext.isAuthorWorkshop {
            updateDisplayedBrowserItems()
        } else {
            navigateToBrowse()
        }
    }

    private func setBrowserQuery(_ query: String) {
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = query
        isUpdatingBrowserQueryProgrammatically = false
        updateDisplayedBrowserItems()
    }

    private func updateDisplayedBrowserItems() {
        guard browseContext.isAuthorWorkshop else {
            displayedBrowserItems = browserItems
            return
        }

        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedBrowserItems = browserItems
            return
        }

        let normalizedQuery = query.localizedLowercase
        displayedBrowserItems = browserItems.filter {
            $0.title.localizedLowercase.contains(normalizedQuery)
            || $0.author.localizedLowercase.contains(normalizedQuery)
            || $0.summary.localizedLowercase.contains(normalizedQuery)
            || $0.descriptionText.localizedLowercase.contains(normalizedQuery)
            || $0.tags.contains(where: { $0.localizedLowercase.contains(normalizedQuery) })
            || $0.id.localizedLowercase.contains(normalizedQuery)
        }

        if displayedBrowserItems.isEmpty, hasMoreBrowserItems, !isLoadingMoreBrowserItems {
            Task { @MainActor [weak self] in
                self?.loadMoreBrowserItemsIfNeeded()
            }
        }
    }

    private func makeDiscoveryBrowseSnapshot() -> SteamWorkshopDiscoveryBrowseSnapshot {
        SteamWorkshopDiscoveryBrowseSnapshot(
            browserItems: browserItems,
            browserState: browserState,
            hasMoreBrowserItems: hasMoreBrowserItems,
            browserNextPage: browserNextPage,
            statusMessage: statusMessage,
            currentPageTitle: currentPageTitle,
            requestedURL: requestedURL,
            browserQuery: browserQuery,
            currentWorkshopItemID: currentWorkshopItemID,
            selectedBrowserItem: selectedBrowserItem,
            prefetchedBrowserPageKeys: prefetchedBrowserPageKeys,
            scrollOffsetY: currentBrowserScrollOffsetY
        )
    }

    private func restoreDiscoveryBrowseSnapshot(
        _ snapshot: SteamWorkshopDiscoveryBrowseSnapshot,
        restoredQuery: String
    ) {
        setBrowserQuery(restoredQuery)
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        browserItems = snapshot.browserItems
        browserState = snapshot.browserState
        hasMoreBrowserItems = snapshot.hasMoreBrowserItems
        browserNextPage = snapshot.browserNextPage
        isLoadingMoreBrowserItems = false
        statusMessage = snapshot.statusMessage
        currentPageTitle = snapshot.currentPageTitle
        requestedURL = snapshot.requestedURL
        currentWorkshopItemID = snapshot.currentWorkshopItemID
        if let selectedID = snapshot.selectedBrowserItem?.id {
            selectedBrowserItem = snapshot.browserItems.first(where: { $0.id == selectedID }) ?? snapshot.selectedBrowserItem
        } else {
            selectedBrowserItem = nil
        }
        prefetchedBrowserPageKeys = snapshot.prefetchedBrowserPageKeys
        pendingBrowserScrollRestoreOffset = snapshot.scrollOffsetY
    }

    private func loadingStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "正在抓取 Wallpaper Engine 创意工坊视频列表…"
        case .authorWorkshop(let authorName, _):
            return "正在抓取 \(authorName) 的创意工坊作品…"
        }
    }

    private func cachedStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "已载入缓存的创意工坊列表"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的工坊缓存列表"
        }
    }

    private func emptyResultsStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "没有抓取到符合条件的视频项目。"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 当前没有抓取到可展示的视频项目。"
        }
    }

    private func baseCardsStatusMessage(for context: SteamWorkshopBrowseContext, count: Int) -> String {
        switch context {
        case .discovery:
            return "已载入 \(count) 张基础卡片，正在补全详情…"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的 \(count) 张基础卡片，正在补全详情…"
        }
    }

    private func completedStatusMessage(
        for context: SteamWorkshopBrowseContext,
        totalCount: Int,
        hasMore: Bool
    ) -> String {
        switch context {
        case .discovery:
            return hasMore ? "已加载 \(totalCount) 个创意工坊视频项目" : "已加载全部 \(totalCount) 个已抓取项目"
        case .authorWorkshop(let authorName, _):
            return hasMore ? "已加载 \(authorName) 的 \(totalCount) 个创意工坊项目" : "已加载 \(authorName) 的全部 \(totalCount) 个已抓取项目"
        }
    }

    private func failureStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "创意工坊列表抓取失败"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 的工坊列表抓取失败"
        }
    }

    private func prefetchStatusMessage(for context: SteamWorkshopBrowseContext, page: Int) -> String {
        switch context {
        case .discovery:
            return "已预加载第 \(page) 页基础卡片，正在补全详细信息…"
        case .authorWorkshop(let authorName, _):
            return "已预加载 \(authorName) 的第 \(page) 页基础卡片，正在补全详细信息…"
        }
    }

    private func browsePageSize(for context: SteamWorkshopBrowseContext) -> Int {
        switch context {
        case .discovery:
            return Constants.browserPageSize
        case .authorWorkshop:
            return Constants.authorWorkshopPageSize
        }
    }




    func fetchBrowserItems(forceRefresh: Bool = false) {
        browserFetchTask?.cancel()
        cancelBrowserDetailHydration()
        browserNextPage = 2
        hasMoreBrowserItems = true
        isLoadingMoreBrowserItems = false
        isRefreshingBrowserFeed = forceRefresh
        prefetchedBrowserPageKeys.removeAll()
        prefetchedBrowserPages.removeAll()
        let browseContext = self.browseContext
        let source = self.source
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter
        let pageSize = browsePageSize(for: browseContext)
        logBrowserDebug(
            "fetchBrowserItems start context=\(browseContext.title) forceRefresh=\(forceRefresh) query=\(query) pageSize=\(pageSize)"
        )

        if let cached = loadBrowserCache(
            context: browseContext,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter
        ) {
            browserItems = cached.items
            prefetchBrowserPreviewImages(for: cached.items, limit: 48)
            browserState = .loaded
            hasMoreBrowserItems = cached.items.count >= pageSize
            browserNextPage = max(2, (cached.items.count / pageSize) + 1)
            statusMessage = cachedStatusMessage(for: browseContext)
            logBrowserDebug(
                "fetchBrowserItems cacheHit context=\(browseContext.title) cachedCount=\(cached.items.count) nextPage=\(browserNextPage) hasMore=\(hasMoreBrowserItems)"
            )
            if !forceRefresh && Date().timeIntervalSince(cached.fetchedAt) < Constants.cacheTTL {
                isRefreshingBrowserFeed = false
                logBrowserDebug("fetchBrowserItems skipRemote context=\(browseContext.title) reason=freshCache")
                return
            }
            if forceRefresh {
                statusMessage = browseContext.isAuthorWorkshop
                    ? "正在刷新作者工坊列表…"
                    : "正在刷新 Steam 创意工坊列表…"
            }
        } else {
            browserState = .loading
            browserItems = []
            statusMessage = loadingStatusMessage(for: browseContext)
        }

        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let pageResult = try await Self.fetchWorkshopStubPage(
                    context: browseContext,
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: 1
                )
                let stubs = pageResult.stubs
                let seededItems = stubs.map(Self.seededBrowserItem)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.browseContext == browseContext else { return }
                    self.isRefreshingBrowserFeed = false
                    self.browserItems = seededItems
                    self.prefetchBrowserPreviewImages(for: seededItems, limit: 48)
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.browserNextPage = 2
                    self.enqueueBrowserDetailHydration(
                        stubs: stubs,
                        context: browseContext,
                        navigationVersion: self.navigationVersion,
                        resetQueue: true
                    )
                    self.logBrowserDebug(
                        "fetchBrowserItems page1Fallback context=\(browseContext.title) stubCount=\(stubs.count) hasMore=\(pageResult.hasMore)"
                    )
                    self.statusMessage = self.browserItems.isEmpty
                        ? self.emptyResultsStatusMessage(for: browseContext)
                        : self.baseCardsStatusMessage(for: browseContext, count: self.browserItems.count)
                }
                await MainActor.run {
                    guard let self else { return }
                    guard self.browseContext == browseContext else { return }
                    self.isRefreshingBrowserFeed = false
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.browserNextPage = 2
                    self.isLoadingMoreBrowserItems = false
                    self.logBrowserDebug(
                        "fetchBrowserItems enqueued context=\(browseContext.title) stubCount=\(stubs.count) hasMore=\(pageResult.hasMore)"
                    )
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        context: browseContext,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage,
                        lookaheadDepth: 1
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.browseContext == browseContext else { return }
                    self.isRefreshingBrowserFeed = false
                    if self.browserItems.isEmpty {
                        self.browserState = .failed(error.localizedDescription)
                    }
                    self.logBrowserDebug(
                        "fetchBrowserItems failed context=\(browseContext.title) currentCount=\(self.browserItems.count) error=\(error.localizedDescription)"
                    )
                    self.statusMessage = self.failureStatusMessage(for: browseContext)
                }
            }
        }
    }

    private func logBrowserDebug(_ message: String) {
        _ = message
    }

    internal func noteUserBrowsingActivity() {
        let candidate = Date().addingTimeInterval(Constants.browserInteractionDeferralInterval)
        if candidate > backgroundDetailDeferralUntil {
            backgroundDetailDeferralUntil = candidate
        }
    }

    internal func prioritizeUserRequestedDetail() {
        backgroundDetailDeferralUntil = Date().addingTimeInterval(Constants.detailRequestDeferralInterval)
    }

    internal func shouldDeferBackgroundDetailWork() -> Bool {
        Date() < backgroundDetailDeferralUntil
            || isRefreshingSelectedBrowserItem
            || isRefreshingSelectedDownloadDetailItem
    }

    private func prefetchBrowserPreviewImages(aroundVisibleIDs ids: [String]) {
        guard !ids.isEmpty, !displayedBrowserItems.isEmpty else { return }
        let items = displayedBrowserItems
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let visibleIndexes = ids.compactMap { indexByID[$0] }.sorted()
        guard let firstVisibleIndex = visibleIndexes.first,
              let lastVisibleIndex = visibleIndexes.last else { return }
        let startIndex = max(0, firstVisibleIndex - 24)
        let endIndex = min(items.count - 1, lastVisibleIndex + 48)
        guard startIndex <= endIndex else { return }
        prefetchBrowserPreviewImages(for: Array(items[startIndex...endIndex]), limit: 72)
    }

    private func prefetchBrowserPreviewImages(for items: [SteamWorkshopBrowserItem], limit: Int) {
        guard !items.isEmpty, limit > 0 else { return }
        let candidates = items.compactMap { item -> (String, URL)? in
            guard let url = item.previewImageURL else { return nil }
            return (item.id, url)
        }
        let ids = Array(candidates.prefix(limit).map(\.0))
        guard ids != lastPreviewPrefetchIDs else { return }
        lastPreviewPrefetchIDs = ids

        for (_, url) in candidates.prefix(limit) {
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            SteamWorkshopPreviewImageCache.shared.prefetchImageData(forKey: cacheKey) {
                SteamWorkshopPreviewRequestCoordinator.shared.prefetchDataSynchronously(from: url)
            }
        }
    }

    func outputIndicatesAuthenticationFailure(_ output: String) -> Bool {
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
            || lowered.contains("please enter your password")
    }

    func outputIndicatesBenignSteamBootstrap(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        guard lowered.contains("loading steam api") || lowered.contains("iopollinghelpers_osx.cpp") else {
            return false
        }
        guard lowered.contains("ok") else {
            return false
        }
        return !outputIndicatesAuthenticationFailure(output)
            && !outputIndicatesAccessRestriction(output)
    }

    func outputIndicatesAccessRestriction(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        return lowered.contains("access denied")
            || lowered.contains("private")
            || lowered.contains("friends only")
            || lowered.contains("permission")
            || lowered.contains("not available")
            || lowered.contains("failed to download item")
    }

    private func loadCachedBrowserItemsIfPossible() {
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = loadBrowserCache(
            context: browseContext,
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

    func clearAllCachedState() {
        browserFetchTask?.cancel()
        browserFetchTask = nil
        cancelBrowserDetailHydration()
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        cancelActiveLoginSession()
        cancelDownloadImmediately(showFeedback: false)
        logoutImmediately()

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: cacheDirectoryURL)
        try? fileManager.removeItem(at: Self.detailCacheDirectoryURL())
        try? fileManager.removeItem(at: runtimeInstallRootURL)
        try? fileManager.removeItem(at: libraryRootURL)
        SteamWorkshopPreviewImageCache.shared.removeAll()
        ThumbnailCache.clearDiskCache()
        Task {
            await Self.authorNameStore.clear()
        }

        browserItems = []
        displayedBrowserItems = []
        pendingBrowserScrollRestoreOffset = nil
        browserState = .idle
        isRefreshingBrowserFeed = false
        previewReloadToken += 1
        isLoadingMoreBrowserItems = false
        hasMoreBrowserItems = true
        browserNextPage = 1
        prefetchedBrowserPageKeys.removeAll()
        prefetchedBrowserPages.removeAll()
        pendingBrowserDetailStubs = []
        pendingBrowserDetailStubIDs.removeAll()
        browserDetailRetryCounts.removeAll()
        lastPreviewPrefetchIDs = []
        prioritizedVisibleBrowserItemIDs = []
        selectedBrowserItem = nil
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
        activeDownloadItemID = nil
        downloads = []
        downloadsQuery = ""
        downloadsSortMode = .updatedAt
        downloadsSortAscending = false
        isDownloadsMultiSelectMode = false
        selectedDownloadID = nil
        selectedDownloadIDs = []
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
        downloadError = nil
        pendingDownloadRequest = nil
        queuedDownloadRequests = []
        activeDownloadWasCancelled = false
        zoomOffset = 0

        browseContext = .discovery
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = ""
        isUpdatingBrowserQueryProgrammatically = false
        suppressAutomaticBrowseNavigation = true
        source = .featured
        trendingWindow = .week
        themeFilter = .all
        ageRatingFilter = .all
        resolutionFilter = .all
        categoryFilter = .all
        suppressAutomaticBrowseNavigation = false

        requestedURL = Self.makeBrowseURL(
            source: source,
            query: "",
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: 1
        )
        navigationVersion += 1
        currentPageTitle = browseContext.title
        statusMessage = "Steam 创意工坊已恢复到初始状态。下次进入时会像首次使用一样重新加载。"
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

    private func cancelBrowserDetailHydration() {
        browserDetailHydrationTask?.cancel()
        browserDetailHydrationTask = nil
        pendingBrowserDetailStubs.removeAll()
        pendingBrowserDetailStubIDs.removeAll()
        browserDetailRetryCounts.removeAll()
    }

    private func enqueueBrowserDetailHydration(
        stubs: [SteamWorkshopBrowseStub],
        context: SteamWorkshopBrowseContext,
        navigationVersion: Int,
        resetQueue: Bool
    ) {
        if resetQueue {
            browserDetailHydrationTask?.cancel()
            browserDetailHydrationTask = nil
            pendingBrowserDetailStubs.removeAll()
            pendingBrowserDetailStubIDs.removeAll()
            browserDetailRetryCounts.removeAll()
        }

        for stub in stubs {
            guard Self.cachedItemNeedsHydration(for: stub) else { continue }
            guard pendingBrowserDetailStubIDs.insert(stub.id).inserted else { continue }
            pendingBrowserDetailStubs.append(stub)
        }

        guard browserDetailHydrationTask == nil else { return }
        browserDetailHydrationTask = Task(priority: .utility) { [weak self] in
            await self?.runBrowserDetailHydrationQueue(
                context: context,
                navigationVersion: navigationVersion
            )
        }
    }

    private func runBrowserDetailHydrationQueue(
        context: SteamWorkshopBrowseContext,
        navigationVersion: Int
    ) async {
        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.navigationVersion == navigationVersion, self.browseContext == context {
                    self.statusMessage = self.completedStatusMessage(
                        for: context,
                        totalCount: self.browserItems.count,
                        hasMore: self.hasMoreBrowserItems
                    )
                    self.saveBrowserCache(
                        context: context,
                        source: self.source,
                        query: self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                        trendingWindow: self.trendingWindow,
                        themeFilter: self.themeFilter,
                        ageRatingFilter: self.ageRatingFilter,
                        resolutionFilter: self.resolutionFilter,
                        categoryFilter: self.categoryFilter,
                        items: self.browserItems
                    )
                }
                self.browserDetailHydrationTask = nil
            }
        }

        while !Task.isCancelled {
            let shouldDefer = await MainActor.run { self.shouldDeferBackgroundDetailWork() }
            if shouldDefer {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }

            let stubs: [SteamWorkshopBrowseStub] = await MainActor.run {
                guard self.navigationVersion == navigationVersion, self.browseContext == context else {
                    self.pendingBrowserDetailStubs.removeAll()
                    self.pendingBrowserDetailStubIDs.removeAll()
                    self.browserDetailRetryCounts.removeAll()
                    return []
                }
                guard !self.pendingBrowserDetailStubs.isEmpty else { return [] }
                let batchCount = min(Constants.detailHydrationBatchSize, self.pendingBrowserDetailStubs.count)
                let nextBatch = Array(self.pendingBrowserDetailStubs.prefix(batchCount))
                self.pendingBrowserDetailStubs.removeFirst(batchCount)
                nextBatch.forEach { self.pendingBrowserDetailStubIDs.remove($0.id) }
                return nextBatch
            }

            guard !stubs.isEmpty else { break }

            do {
                let items = try await Self.fetchWorkshopItems(
                    stubs: stubs,
                    requestPriority: .background
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == navigationVersion, self.browseContext == context else { return }
                    for item in items {
                        self.browserDetailRetryCounts[item.id] = nil
                        self.mergeBrowserItem(item)
                        if self.selectedBrowserItem?.id == item.id {
                            self.selectedBrowserItem = item
                            self.selectedBrowserItemError = nil
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: Constants.detailHydrationInterBatchDelayNanoseconds)
            } catch {
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                let shouldRetry = nsError.domain == NSURLErrorDomain && nsError.code == 429
                let attempt = await MainActor.run { () -> Int in
                    var highestAttempt = 0
                    for stub in stubs {
                        let next = (self.browserDetailRetryCounts[stub.id] ?? 0) + 1
                        self.browserDetailRetryCounts[stub.id] = next
                        highestAttempt = max(highestAttempt, next)
                    }
                    return highestAttempt
                }

                if shouldRetry, attempt <= 4 {
                    await MainActor.run {
                        for stub in stubs.reversed() {
                            if self.pendingBrowserDetailStubIDs.insert(stub.id).inserted {
                                self.pendingBrowserDetailStubs.insert(stub, at: 0)
                            }
                        }
                        self.logBrowserDebug(
                            "detail hydration rate-limited batchCount=\(stubs.count) attempt=\(attempt) queueCount=\(self.pendingBrowserDetailStubs.count)"
                        )
                    }
                    let backoffSeconds = UInt64(min(20, attempt * 4))
                    try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                    continue
                }

                await MainActor.run {
                    self.logBrowserDebug(
                        "detail hydration failed batchCount=\(stubs.count) code=\(nsError.code) domain=\(nsError.domain) error=\(nsError.localizedDescription)"
                    )
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func needsDetailRefresh(for item: SteamWorkshopBrowserItem) -> Bool {
        item.detailFields.isEmpty
        || item.fileSizeText == nil
        || item.resolutionText == nil
        || item.workshopTypeText == nil
        || item.author == "未知作者"
        || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
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
            authorWorkshopURL: item.authorWorkshopURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            previewImageURL: item.previewImageURL
        )

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.selectedBrowserItem = refreshed
                    self.mergeBrowserItem(refreshed)
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

    func refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedDownloadInspectorItem else { return }
        if !forceRefresh && !needsDetailRefresh(for: item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedDownloadDetailItem = true
        selectedDownloadDetailError = nil

        let stub = SteamWorkshopBrowseStub(
            id: item.id,
            title: item.title,
            author: item.author,
            authorProfileURL: item.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            previewImageURL: item.previewImageURL
        )

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.selectedDownloadDetailItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = error.localizedDescription
                }
            }
        }
    }

    private func prefetchUpcomingBrowserPageIfNeeded(
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int,
        lookaheadDepth: Int = 0
    ) {
        guard page > 1 else { return }
        let key = browserPagePrefetchKey(
            context: context,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page
        )
        guard prefetchedBrowserPageKeys.insert(key).inserted else { return }

        Task(priority: .utility) {
            guard let pageResult = try? await Self.fetchWorkshopStubPage(
                context: context,
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page
            ), !pageResult.stubs.isEmpty else {
                return
            }
            await MainActor.run {
                guard self.browseContext == context,
                      self.source == source,
                      self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.trendingWindow == trendingWindow,
                      self.themeFilter == themeFilter,
                      self.ageRatingFilter == ageRatingFilter,
                      self.resolutionFilter == resolutionFilter,
                      self.categoryFilter == categoryFilter else {
                    return
                }
                self.prefetchedBrowserPages[key] = pageResult
                let seededItems = pageResult.stubs.map(Self.seededBrowserItem)
                self.prefetchBrowserPreviewImages(for: seededItems, limit: 36)
            }
            let shouldDeferDetailPrefetch = await MainActor.run { self.shouldDeferBackgroundDetailWork() }
            guard !shouldDeferDetailPrefetch else { return }
            try? await Self.prewarmDetailCache(for: pageResult.stubs)
            guard lookaheadDepth > 0, pageResult.hasMore else { return }
            await MainActor.run {
                self.prefetchUpcomingBrowserPageIfNeeded(
                    context: context,
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: page + 1,
                    lookaheadDepth: lookaheadDepth - 1
                )
            }
        }
    }

    private func browserPagePrefetchKey(
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) -> String {
        "\(context.cacheKeyComponent)|\(source.rawValue)|\(trendingWindow.rawValue)|\(themeFilter.rawValue)|\(ageRatingFilter.rawValue)|\(resolutionFilter.rawValue)|\(categoryFilter.rawValue)|\(query)|\(page)"
    }

    private func loadBrowserCache(
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter
    ) -> SteamWorkshopBrowserCacheSnapshot? {
        let url = cacheFileURL(
            context: context,
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
        context: SteamWorkshopBrowseContext,
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
                context: context,
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
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter
    ) -> URL {
        switch context {
        case .discovery:
            break
        case .authorWorkshop:
            return cacheDirectoryURL.appendingPathComponent("\(context.cacheKeyComponent).json")
        }
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

    static func detailCacheDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("ItemDetails", isDirectory: true)
    }

    static func detailCacheFileURL(id: String) -> URL {
        detailCacheDirectoryURL().appendingPathComponent("\(id).json")
    }

    static func legacyDownloadMetadataFileURL(for directory: URL) -> URL {
        directory.appendingPathComponent(".mywallpaperx-steam-metadata.json")
    }

    func downloadMetadataIndexDirectoryURL() -> URL {
        libraryRootURL.appendingPathComponent(".mywallpaperx-steam-metadata", isDirectory: true)
    }

    func downloadMetadataFileURL(for itemID: String) -> URL {
        downloadMetadataIndexDirectoryURL().appendingPathComponent("\(itemID).json")
    }

    static func loadDetailCache(id: String) -> SteamWorkshopBrowserItem? {
        let url = detailCacheFileURL(id: id)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDetailCacheSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.fetchedAt) < Constants.detailCacheTTL else {
            return nil
        }
        return snapshot.item
    }

    static func saveDetailCache(item: SteamWorkshopBrowserItem) {
        let snapshot = SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: item)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = detailCacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: detailCacheFileURL(id: item.id), options: [.atomic])
    }

    func buildInstalledRecord(at directory: URL) -> SteamWorkshopDownloadRecord? {
        let projectURL = directory.appendingPathComponent("project.json")
        let metadataURL = Self.legacyDownloadMetadataFileURL(for: directory)
        guard FileManager.default.fileExists(atPath: projectURL.path)
                || FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        let project = try? JSONDecoder().decode(SteamWorkshopProject.self, from: Data(contentsOf: projectURL))
        let identifier = project?.workshopid ?? directory.lastPathComponent
        let metadata = loadDownloadMetadataSnapshot(legacyDirectory: directory, id: identifier)
        return buildInstalledRecord(
            from: metadata,
            legacyDirectory: directory,
            fallbackProject: project,
            fallbackIdentifier: identifier
        )
    }

    func resolveVideoURL(in directory: URL, preferredFileName: String?) -> URL? {
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

    func upsertTransientRecord(
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
                sourceVideoURL: previous.sourceVideoURL,
                exportedVideoURL: previous.exportedVideoURL,
                updatedAt: Date(),
                sizeText: sizeText ?? previous.sizeText,
                status: status,
                browserItem: previous.browserItem
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
                sourceVideoURL: nil,
                exportedVideoURL: nil,
                updatedAt: Date(),
                sizeText: sizeText ?? "等待下载",
                status: status,
                browserItem: browserItemForDownload(id: id)
            ),
            at: 0
        )
    }

    func buildInstalledRecord(
        from metadata: SteamWorkshopDownloadMetadataSnapshot?,
        legacyDirectory: URL?,
        fallbackProject: SteamWorkshopProject?,
        fallbackIdentifier: String
    ) -> SteamWorkshopDownloadRecord? {
        let identifier = metadata?.item.id ?? fallbackProject?.workshopid ?? fallbackIdentifier
        let resolvedLegacyDirectory: URL? = {
            if let legacyFolderURL = metadata?.legacyFolderURL,
               FileManager.default.fileExists(atPath: legacyFolderURL.path) {
                return legacyFolderURL
            }
            if let legacyDirectory,
               FileManager.default.fileExists(atPath: legacyDirectory.path) {
                return legacyDirectory
            }
            return nil
        }()

        let previewURL: URL? = {
            if let previewRelativePath = metadata?.previewRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(previewRelativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let preview = fallbackProject?.preview,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(preview)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }()

        let sourceVideoURL: URL? = {
            if let sourceVideoRelativePath = metadata?.sourceVideoRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(sourceVideoRelativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let resolvedLegacyDirectory {
                return resolveVideoURL(in: resolvedLegacyDirectory, preferredFileName: fallbackProject?.file)
            }
            return nil
        }()

        let exportedVideoURL = metadata?.exportedVideoURL.flatMap { url in
            FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let effectiveVideoURL = exportedVideoURL ?? sourceVideoURL
        guard metadata != nil || effectiveVideoURL != nil else {
            return nil
        }

        let updatedAt: Date = {
            if let effectiveVideoURL,
               let values = try? effectiveVideoURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate {
                return date
            }
            if let resolvedLegacyDirectory,
               let values = try? resolvedLegacyDirectory.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate {
                return date
            }
            return Date()
        }()

        let title = fallbackProject?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = fallbackProject?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = fallbackProject?.tags ?? []
        let sizeText = effectiveVideoURL.flatMap { fileSizeText(for: $0) } ?? "未知大小"
        let browserItem = metadata?.item ?? browserItemForDownload(id: identifier)

        let browserTitle = browserItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : (browserTitle.isEmpty ? "Workshop #\(identifier)" : browserTitle),
            description: description.isEmpty ? (browserItem?.descriptionText ?? "") : description,
            tags: tags.isEmpty ? (browserItem?.tags ?? []) : tags,
            folderURL: resolvedLegacyDirectory ?? effectiveVideoURL?.deletingLastPathComponent() ?? libraryRootURL,
            previewURL: previewURL,
            sourceVideoURL: sourceVideoURL,
            exportedVideoURL: exportedVideoURL,
            updatedAt: updatedAt,
            sizeText: sizeText,
            status: .ready,
            browserItem: browserItem
        )
    }

    private func loadDownloadMetadataSnapshot(legacyDirectory: URL?, id: String) -> SteamWorkshopDownloadMetadataSnapshot? {
        let metadataURL = downloadMetadataFileURL(for: id)
        if let data = try? Data(contentsOf: metadataURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
            return snapshot
        }

        if let legacyDirectory {
            let metadataURL = Self.legacyDownloadMetadataFileURL(for: legacyDirectory)
            if let data = try? Data(contentsOf: metadataURL),
               let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
                return snapshot
            }
        }

        guard let item = browserItemForDownload(id: id) else { return nil }
        return SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: .distantPast,
            item: item,
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: nil,
            legacyFolderURL: legacyDirectory
        )
    }

    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? {
        if let selectedBrowserItem, selectedBrowserItem.id == id {
            return selectedBrowserItem
        }
        if let browserItem = browserItems.first(where: { $0.id == id }) {
            return browserItem
        }
        return Self.loadDetailCache(id: id)
    }

    private static func cachedItemNeedsHydration(for stub: SteamWorkshopBrowseStub) -> Bool {
        guard let cached = loadDetailCache(id: stub.id) else { return true }
        let merged = mergeStub(stub, into: cached)
        return merged.detailFields.isEmpty
            || merged.fileSizeText == nil
            || merged.resolutionText == nil
            || merged.workshopTypeText == nil
            || merged.author == "未知作者"
            || (merged.authorProfileURL == nil && merged.authorWorkshopURL == nil)
    }

    static func applyingCachedAuthorNameIfPossible(to item: SteamWorkshopBrowserItem) async -> SteamWorkshopBrowserItem {
        guard item.author == "未知作者" else { return item }
        let keys = authorCacheKeys(
            creatorID: creatorID(from: item.authorProfileURL) ?? creatorID(from: item.authorWorkshopURL),
            authorProfileURL: item.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL
        )
        guard let cachedAuthorName = await Self.authorNameStore.name(for: keys) else { return item }
        return SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title,
            author: cachedAuthorName,
            authorProfileURL: item.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL,
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
            previewAssetKind: item.previewAssetKind,
            fileSizeText: item.fileSizeText,
            resolutionText: item.resolutionText,
            postedText: item.postedText,
            updatedText: item.updatedText,
            favoritesText: item.favoritesText,
            subscriptionsText: item.subscriptionsText,
            scoreText: item.scoreText,
            lifetimeFavoritesText: item.lifetimeFavoritesText,
            lifetimeSubscriptionsText: item.lifetimeSubscriptionsText,
            visibilityText: item.visibilityText,
            moderationText: item.moderationText,
            detailFields: item.detailFields,
            detailURL: item.detailURL
        )
    }

    static func resolvedAuthorName(
        creatorID: String?,
        stub: SteamWorkshopBrowseStub,
        authorProfileURL: URL?,
        authorWorkshopURL: URL?
    ) async -> String {
        let stubAuthor = normalizedStubAuthor(
            SteamWorkshopBrowseStub(
                id: stub.id,
                title: stub.title,
                author: stub.author,
                authorProfileURL: authorProfileURL ?? stub.authorProfileURL,
                authorWorkshopURL: authorWorkshopURL ?? stub.authorWorkshopURL,
                hasAdultContent: stub.hasAdultContent,
                summary: stub.summary,
                previewImageURL: stub.previewImageURL
            )
        )

        if stubAuthor != "未知作者" {
            await saveAuthorNameIfPossible(
                stubAuthor,
                creatorID: creatorID,
                authorProfileURL: authorProfileURL ?? stub.authorProfileURL,
                authorWorkshopURL: authorWorkshopURL ?? stub.authorWorkshopURL
            )
            return stubAuthor
        }

        let keys = authorCacheKeys(
            creatorID: creatorID,
            authorProfileURL: authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: authorWorkshopURL ?? stub.authorWorkshopURL
        )
        if let cachedName = await Self.authorNameStore.name(for: keys) {
            return cachedName
        }
        return stubAuthor
    }

    static func saveAuthorNameIfPossible(
        _ authorName: String?,
        creatorID: String?,
        authorProfileURL: URL?,
        authorWorkshopURL: URL?
    ) async {
        guard let authorName else { return }
        let normalizedName = normalizeAuthorName(authorName)
        let keys = authorCacheKeys(
            creatorID: creatorID,
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL
        )
        await Self.authorNameStore.store(name: normalizedName, for: keys)
    }

    static func authorCacheKeys(
        creatorID explicitCreatorID: String?,
        authorProfileURL: URL?,
        authorWorkshopURL: URL?
    ) -> [String] {
        var keys: [String] = []
        if let explicitCreatorID, !explicitCreatorID.isEmpty {
            keys.append("creator:\(explicitCreatorID)")
        }
        if let authorProfileURL {
            keys.append("profile:\((normalizeSteamCommunityURL(authorProfileURL.absoluteString) ?? authorProfileURL).absoluteString.lowercased())")
        }
        if let normalizedWorkshopURL = normalizedAuthorWorkshopURL(authorWorkshopURL) {
            keys.append("workshop:\(normalizedWorkshopURL.absoluteString.lowercased())")
        }
        if let profileCreatorID = creatorID(from: authorProfileURL) {
            keys.append("creator:\(profileCreatorID)")
        }
        if let workshopCreatorID = creatorID(from: authorWorkshopURL) {
            keys.append("creator:\(workshopCreatorID)")
        }
        return Array(NSOrderedSet(array: keys)) as? [String] ?? keys
    }

    static func creatorID(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.absoluteURL.pathComponents
        guard let profilesIndex = components.firstIndex(of: "profiles"),
              components.indices.contains(profilesIndex + 1) else {
            return nil
        }
        let candidate = components[profilesIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return candidate.isEmpty ? nil : candidate
    }
}
