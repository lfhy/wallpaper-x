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
    private static let authorNameStore = SteamWorkshopAuthorNameStore()

    private enum Constants {
        static let workshopAppID = "431960"
        static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        static let publishedFileDetailsAPI = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
        static let authorWorkshopPageSize = 30
        static let detailHydrationBatchSize = 12
        static let detailHydrationInterBatchDelayNanoseconds: UInt64 = 700_000_000
        static let detailPrefetchBatchSize = 8
        static let detailPrefetchInterBatchDelayNanoseconds: UInt64 = 1_100_000_000
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

    @Published private(set) var browserItems: [SteamWorkshopBrowserItem] = [] {
        didSet { updateDisplayedBrowserItems() }
    }
    @Published private(set) var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    @Published private(set) var pendingBrowserScrollRestoreOffset: CGFloat?
    @Published private(set) var browserState: SteamWorkshopBrowserLoadState = .idle
    @Published private(set) var isLoadingMoreBrowserItems = false
    @Published private(set) var hasMoreBrowserItems = true
    @Published private(set) var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var source: SteamWorkshopSource = .featured {
        didSet { navigateToBrowse() }
    }
    @Published var browserQuery: String = "" {
        didSet {
            guard !isUpdatingBrowserQueryProgrammatically else { return }
            handleBrowserQueryChanged()
        }
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
    @Published private(set) var browserSectionTitle: String = "Steam 创意工坊"
    @Published private(set) var isBrowsingAuthorWorkshop = false
    @Published private(set) var activeAuthorWorkshopName: String?
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
    private var browserDetailHydrationTask: Task<Void, Never>?
    private var browserNextPage = 1
    private var prefetchedBrowserPageKeys = Set<String>()
    private var pendingBrowserDetailStubs: [SteamWorkshopBrowseStub] = []
    private var pendingBrowserDetailStubIDs = Set<String>()
    private var browserDetailRetryCounts: [String: Int] = [:]
    private var prioritizedVisibleBrowserItemIDs: [String] = []
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
    private var discoveryBrowseSnapshot: SteamWorkshopDiscoveryBrowseSnapshot?
    private var currentBrowserScrollOffsetY: CGFloat = 0
    private var savedDiscoveryQueryBeforeAuthorBrowse: String?
    private var isUpdatingBrowserQueryProgrammatically = false
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

    var activeBrowserContextSummary: String? {
        guard let activeAuthorWorkshopName else { return nil }
        return "当前正在浏览 \(activeAuthorWorkshopName) 的创意工坊作品"
    }

    var hasVisibleBrowserItems: Bool {
        !displayedBrowserItems.isEmpty
    }

    func isDownloading(itemID: String) -> Bool {
        activeDownloadItemID == itemID
    }

    func latestDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        downloads.first(where: { $0.id == itemID })
    }

    func downloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              record.status == .ready else {
            return nil
        }
        return record
    }

    func isDownloaded(itemID: String) -> Bool {
        downloadRecord(for: itemID) != nil
    }

    func latestDownloadFailure(for itemID: String) -> String? {
        latestDownloadRecord(for: itemID)?.failureMessage
    }

    func downloadProgressLabel(for itemID: String) -> String? {
        guard activeDownloadItemID == itemID else { return nil }
        return activeDownloadProgressText
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

        logBrowserDebug(
            "loadMore start context=\(browseContext.title) page=\(page) query=\(query) currentCount=\(browserItems.count) hasMore=\(hasMoreBrowserItems)"
        )
        isLoadingMoreBrowserItems = true

        Task(priority: .userInitiated) { [weak self] in
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
                    page: page
                )
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
                        page: self.browserNextPage
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
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
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
        cancelBrowserDetailHydration()
        browserNextPage = 2
        hasMoreBrowserItems = true
        isLoadingMoreBrowserItems = false
        prefetchedBrowserPageKeys.removeAll()
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
            browserState = .loaded
            hasMoreBrowserItems = cached.items.count >= pageSize
            browserNextPage = max(2, (cached.items.count / pageSize) + 1)
            statusMessage = cachedStatusMessage(for: browseContext)
            logBrowserDebug(
                "fetchBrowserItems cacheHit context=\(browseContext.title) cachedCount=\(cached.items.count) nextPage=\(browserNextPage) hasMore=\(hasMoreBrowserItems)"
            )
            if !forceRefresh && Date().timeIntervalSince(cached.fetchedAt) < Constants.cacheTTL {
                logBrowserDebug("fetchBrowserItems skipRemote context=\(browseContext.title) reason=freshCache")
                return
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
                    self.browserItems = seededItems
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
                        page: self.browserNextPage
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.browseContext == browseContext else { return }
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

    private func resetSteamAuthDebugLog() {}

    private func appendSteamAuthDebugLog(_ message: String) {
        _ = message
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

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: cacheDirectoryURL)
        try? fileManager.removeItem(at: Self.detailCacheDirectoryURL())
        Task {
            await Self.authorNameStore.clear()
        }

        browserItems = []
        displayedBrowserItems = []
        pendingBrowserScrollRestoreOffset = nil
        browserState = .idle
        isLoadingMoreBrowserItems = false
        hasMoreBrowserItems = true
        browserNextPage = 1
        prefetchedBrowserPageKeys.removeAll()
        prioritizedVisibleBrowserItemIDs = []
        selectedBrowserItem = nil
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        currentWorkshopItemID = nil

        browseContext = .discovery
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = ""
        isUpdatingBrowserQueryProgrammatically = false

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
        statusMessage = "Steam 创意工坊缓存已清空，重新进入模块后会重新抓取列表。"

        reloadInstalledItems()
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
                let items = try await Self.fetchWorkshopItems(stubs: stubs)
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

    private func needsDetailRefresh(for item: SteamWorkshopBrowserItem) -> Bool {
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
                let refreshed = try await Self.fetchWorkshopItem(stub: stub)
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

    private func prefetchUpcomingBrowserPageIfNeeded(
        context: SteamWorkshopBrowseContext,
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
        let key = "\(context.cacheKeyComponent)|\(source.rawValue)|\(trendingWindow.rawValue)|\(themeFilter.rawValue)|\(ageRatingFilter.rawValue)|\(resolutionFilter.rawValue)|\(categoryFilter.rawValue)|\(query)|\(page)"
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
            try? await Self.prewarmDetailCache(for: pageResult.stubs)
        }
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
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "searchtext", value: "")
        ]
        return components.url!
    }

    private static func makeAuthorWorkshopURL(baseURL: URL, page: Int) -> URL {
        let normalizedURL = normalizedAuthorWorkshopURL(baseURL) ?? baseURL
        guard var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false) else {
            return normalizedURL
        }
        var queryItems = (components.queryItems ?? []).filter { $0.name != "p" && $0.name != "appid" && $0.name != "numperpage" }
        queryItems.insert(URLQueryItem(name: "appid", value: Constants.workshopAppID), at: 0)
        queryItems.append(URLQueryItem(name: "p", value: "\(max(1, page))"))
        queryItems.append(URLQueryItem(name: "numperpage", value: "\(Constants.authorWorkshopPageSize)"))
        components.queryItems = queryItems
        return components.url ?? normalizedURL
    }

    private static func fetchWorkshopStubPage(
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) async throws -> SteamWorkshopBrowseStubPage {
        let url: URL
        switch context {
        case .discovery:
            url = makeBrowseURL(
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page
            )
        case .authorWorkshop(_, let workshopURL):
            url = makeAuthorWorkshopURL(baseURL: workshopURL, page: page)
        }
        let html = try await fetchHTML(url: url)
        let stubs = parseBrowsePage(html: html)
        for stub in stubs {
            await saveAuthorNameIfPossible(
                stub.author,
                creatorID: creatorID(from: stub.authorProfileURL) ?? creatorID(from: stub.authorWorkshopURL),
                authorProfileURL: stub.authorProfileURL,
                authorWorkshopURL: stub.authorWorkshopURL
            )
        }
        let pageSize = context.isAuthorWorkshop ? Constants.authorWorkshopPageSize : Constants.browserPageSize
        let hasMore = browsePageHasMore(html: html, currentPage: page) || stubs.count >= pageSize
        if !stubs.isEmpty {
            return SteamWorkshopBrowseStubPage(stubs: stubs, hasMore: hasMore)
        }

        let pattern = #"sharedfiles/filedetails/\?id=(\d+)"#
        let matches = firstCaptureMatches(pattern: pattern, in: html)
        var ordered: [SteamWorkshopBrowseStub] = []
        var seen = Set<String>()
        for id in matches where seen.insert(id).inserted {
            ordered.append(
                SteamWorkshopBrowseStub(
                    id: id,
                    title: nil,
                    author: nil,
                    authorProfileURL: nil,
                    authorWorkshopURL: nil,
                    hasAdultContent: false,
                    summary: nil,
                    previewImageURL: nil
                )
            )
        }
        return SteamWorkshopBrowseStubPage(stubs: ordered, hasMore: hasMore)
    }

    private static func fetchWorkshopItems(stubs: [SteamWorkshopBrowseStub]) async throws -> [SteamWorkshopBrowserItem] {
        guard !stubs.isEmpty else { return [] }
        var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
        var unresolvedStubs: [SteamWorkshopBrowseStub] = []
        itemsByID.reserveCapacity(stubs.count)
        unresolvedStubs.reserveCapacity(stubs.count)

        for stub in stubs {
            if let cached = loadDetailCache(id: stub.id) {
                let merged = mergeStub(stub, into: cached)
                let enriched = try await enrichPreviewKind(for: merged)
                if enriched != cached {
                    saveDetailCache(item: enriched)
                }
                itemsByID[stub.id] = enriched
            } else {
                unresolvedStubs.append(stub)
            }
        }

        let detailsByID = try await fetchPublishedFileDetails(ids: unresolvedStubs.map(\.id))
        let missingIDs = unresolvedStubs.map(\.id).filter { detailsByID[$0] == nil }
        if !missingIDs.isEmpty {
            NSLog(
                "[SteamWorkshopService] official details missing requested=%ld returned=%ld missing=%@",
                unresolvedStubs.count,
                detailsByID.count,
                missingIDs.joined(separator: ",")
            )
        }
        for stub in unresolvedStubs {
            if let detail = detailsByID[stub.id] {
                let item = try await fetchWorkshopItem(
                    stub: stub,
                    officialDetail: detail,
                    allowHTMLFallback: false
                )
                itemsByID[stub.id] = item
                continue
            }

            do {
                let item = try await fetchWorkshopItem(
                    stub: stub,
                    officialDetail: nil,
                    allowHTMLFallback: true
                )
                itemsByID[stub.id] = item
            } catch {
                let fallback = fallbackBrowserItem(from: stub)
                let enrichedFallback = try await enrichPreviewKind(for: fallback)
                itemsByID[stub.id] = enrichedFallback
            }
        }

        return stubs.compactMap { itemsByID[$0.id] }
    }

    private static func prewarmDetailCache(for stubs: [SteamWorkshopBrowseStub]) async throws {
        let uncachedStubs = stubs.filter { loadDetailCache(id: $0.id) == nil }
        guard !uncachedStubs.isEmpty else { return }

        var startIndex = 0
        while startIndex < uncachedStubs.count {
            let endIndex = min(startIndex + Constants.detailPrefetchBatchSize, uncachedStubs.count)
            let batch = Array(uncachedStubs[startIndex..<endIndex])
            let detailsByID = try await fetchPublishedFileDetails(ids: batch.map(\.id))
            for stub in batch {
                guard let detail = detailsByID[stub.id], detailRepresentsVideo(detail) else { continue }
                let item = await item(from: detail, stub: stub)
                saveDetailCache(item: item)
            }
            startIndex = endIndex
            if startIndex < uncachedStubs.count {
                try? await Task.sleep(nanoseconds: Constants.detailPrefetchInterBatchDelayNanoseconds)
            }
        }
    }

    private static func fetchWorkshopItem(
        stub: SteamWorkshopBrowseStub,
        officialDetail: SteamWorkshopPublishedFileDetail? = nil,
        allowHTMLFallback: Bool = true
    ) async throws -> SteamWorkshopBrowserItem {
        if let cached = loadDetailCache(id: stub.id) {
            let merged = await applyingCachedAuthorNameIfPossible(to: mergeStub(stub, into: cached))
            let enriched = try await enrichPreviewKind(for: merged)
            if enriched != cached {
                saveDetailCache(item: enriched)
            }
            return enriched
        }

        let detail = if let officialDetail {
            officialDetail
        } else {
            try await fetchPublishedFileDetails(ids: [stub.id])[stub.id]
        }

        var resolvedItem: SteamWorkshopBrowserItem
        if let detail {
            if !detailRepresentsVideo(detail) {
                throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "当前条目不是视频壁纸。"
                ])
            }
            resolvedItem = await item(from: detail, stub: stub)
        } else {
            resolvedItem = fallbackBrowserItem(from: stub)
        }

        if allowHTMLFallback, shouldSupplementWithHTML(item: resolvedItem) {
            do {
                let htmlItem = try await fetchWorkshopItemFromHTML(stub: stub)
                await saveAuthorNameIfPossible(
                    htmlItem.author,
                    creatorID: detail?.creator,
                    authorProfileURL: htmlItem.authorProfileURL ?? stub.authorProfileURL,
                    authorWorkshopURL: htmlItem.authorWorkshopURL ?? stub.authorWorkshopURL
                )
                resolvedItem = mergeDetailedItem(preferred: htmlItem, fallback: resolvedItem)
            } catch {
                // 官方接口成功时，不因为 HTML 兜底失败而让详情整体失败。
            }
        }

        let merged = mergeStub(stub, into: resolvedItem)
        let enriched = try await enrichPreviewKind(for: merged)
        saveDetailCache(item: enriched)
        return enriched
    }

    private static func fetchWorkshopItemFromHTML(stub: SteamWorkshopBrowseStub) async throws -> SteamWorkshopBrowserItem {
        let detailURL = makeDetailURL(id: stub.id)
        let html = try await fetchHTML(url: detailURL)
        let parsed = parseDetailPage(html: html, fallbackID: stub.id)
        if let workshopTypeText = parsed.workshopTypeText,
           !workshopTypeText.localizedCaseInsensitiveContains("video") {
            throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "当前条目详情页标记类型为 \(workshopTypeText)，不是视频壁纸。"
            ])
        }
        return SteamWorkshopBrowserItem(
            id: stub.id,
            title: parsed.title,
            author: parsed.author,
            authorProfileURL: parsed.authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: parsed.authorWorkshopURL ?? stub.authorWorkshopURL,
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
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: parsed.detailFields,
            detailURL: detailURL
        )
    }

    private static func fetchPublishedFileDetails(ids: [String]) async throws -> [String: SteamWorkshopPublishedFileDetail] {
        let normalizedIDs = Array(NSOrderedSet(array: ids.filter { !$0.isEmpty })) as? [String] ?? []
        guard !normalizedIDs.isEmpty else { return [:] }

        var request = URLRequest(url: URL(string: Constants.publishedFileDetailsAPI)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")

        var formItems = ["itemcount=\(normalizedIDs.count)"]
        formItems.append(contentsOf: normalizedIDs.enumerated().map { index, id in
            "publishedfileids[\(index)]=\(id)"
        })
        request.httpBody = formItems.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Steam 官方详情接口请求失败，HTTP \(http.statusCode)"
                ]
            )
        }

        let decoded = try JSONDecoder().decode(SteamWorkshopPublishedFileResponseEnvelope.self, from: data)
        var result: [String: SteamWorkshopPublishedFileDetail] = [:]
        for detail in decoded.response.publishedfiledetails where detail.result == 1 {
            result[detail.publishedfileid] = detail
        }
        return result
    }

    private static func item(from detail: SteamWorkshopPublishedFileDetail, stub: SteamWorkshopBrowseStub) async -> SteamWorkshopBrowserItem {
        let tags = detail.tags.map(\.tag).map(normalizeText).filter { !$0.isEmpty }
        let authorProfileURL = detail.creator.flatMap { creator in
            URL(string: "https://steamcommunity.com/profiles/\(creator)/")
        }
        let authorWorkshopURL = detail.creator.flatMap { creator in
            URL(string: "https://steamcommunity.com/profiles/\(creator)/myworkshopfiles/?appid=\(Constants.workshopAppID)")
        }
        let resolvedAuthor = await resolvedAuthorName(
            creatorID: detail.creator,
            stub: stub,
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL
        )
        let descriptionText = normalizeText(detail.description ?? "")
        let summaryText = stub.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summaryText?.isEmpty == false ? summaryText! : descriptionText
        let workshopType = preferredTag(in: tags, matching: ["Video"])
        let ageRating = preferredTag(in: tags, matching: SteamWorkshopAgeRatingFilter.allCases.map(\.rawValue))
        let category = preferredTag(in: tags, matching: SteamWorkshopCategoryFilter.allCases.dropFirst().map(\.rawValue))
        let resolution = tags.first(where: isResolutionTag)
        let genre = tags.first(where: { tag in
            !isSystemWorkshopTag(tag)
        })
        let subscriptions = detail.subscriptions
        let favorites = detail.favorited
        let lifetimeSubscriptions = detail.lifetimeSubscriptions
        let lifetimeFavorites = detail.lifetimeFavorited
        let scoreText = detail.views.map { "浏览 \($0)" }
        let visibilityText = visibilityText(for: detail.visibility)
        let moderationText = moderationText(banned: detail.banned, banReason: detail.banReason)

        return SteamWorkshopBrowserItem(
            id: detail.publishedfileid,
            title: normalizeText(detail.title ?? normalizedStubTitle(stub)),
            author: resolvedAuthor,
            authorProfileURL: authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: authorWorkshopURL ?? stub.authorWorkshopURL,
            hasAdultContent: stub.hasAdultContent,
            summary: summary,
            descriptionText: descriptionText.isEmpty ? summary : descriptionText,
            tags: tags,
            workshopTypeText: workshopType,
            ageRatingText: ageRating,
            genreText: genre,
            categoryText: category,
            previewImageURL: detail.previewURL ?? stub.previewImageURL,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: detail.fileSize.map(fileSizeText(forBytes:)),
            resolutionText: resolution,
            postedText: formatSteamTimestamp(detail.timeCreated),
            updatedText: formatSteamTimestamp(detail.timeUpdated),
            favoritesText: favorites.map(formatCount),
            subscriptionsText: subscriptions.map(formatCount),
            scoreText: scoreText,
            lifetimeFavoritesText: lifetimeFavorites.map(formatCount),
            lifetimeSubscriptionsText: lifetimeSubscriptions.map(formatCount),
            visibilityText: visibilityText,
            moderationText: moderationText,
            detailFields: buildOfficialDetailFields(
                fileSizeText: detail.fileSize.map(fileSizeText(forBytes:)),
                resolutionText: resolution,
                postedText: formatSteamTimestamp(detail.timeCreated),
                updatedText: formatSteamTimestamp(detail.timeUpdated),
                subscriptionsText: subscriptions.map(formatCount),
                favoritesText: favorites.map(formatCount),
                lifetimeSubscriptionsText: lifetimeSubscriptions.map(formatCount),
                lifetimeFavoritesText: lifetimeFavorites.map(formatCount),
                visibilityText: visibilityText,
                moderationText: moderationText,
                tags: tags
            ),
            detailURL: makeDetailURL(id: detail.publishedfileid)
        )
    }

    private static func detailRepresentsVideo(_ detail: SteamWorkshopPublishedFileDetail) -> Bool {
        detail.tags.contains { $0.tag.localizedCaseInsensitiveContains("Video") }
    }

    private static func shouldSupplementWithHTML(item: SteamWorkshopBrowserItem) -> Bool {
        item.author == "未知作者"
            || item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || item.authorWorkshopURL == nil
    }

    private static func mergeDetailedItem(
        preferred: SteamWorkshopBrowserItem,
        fallback: SteamWorkshopBrowserItem
    ) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: preferred.id,
            title: preferred.title.isEmpty ? fallback.title : preferred.title,
            author: preferred.author == "未知作者" ? fallback.author : preferred.author,
            authorProfileURL: preferred.authorProfileURL ?? fallback.authorProfileURL,
            authorWorkshopURL: preferred.authorWorkshopURL ?? fallback.authorWorkshopURL,
            hasAdultContent: preferred.hasAdultContent || fallback.hasAdultContent,
            summary: preferred.summary.isEmpty ? fallback.summary : preferred.summary,
            descriptionText: preferred.descriptionText.isEmpty ? fallback.descriptionText : preferred.descriptionText,
            tags: preferred.tags.isEmpty ? fallback.tags : preferred.tags,
            workshopTypeText: preferred.workshopTypeText ?? fallback.workshopTypeText,
            ageRatingText: preferred.ageRatingText ?? fallback.ageRatingText,
            genreText: preferred.genreText ?? fallback.genreText,
            categoryText: preferred.categoryText ?? fallback.categoryText,
            previewImageURL: preferred.previewImageURL ?? fallback.previewImageURL,
            previewVideoURL: preferred.previewVideoURL ?? fallback.previewVideoURL,
            previewAssetKind: preferred.previewAssetKind == .unknown ? fallback.previewAssetKind : preferred.previewAssetKind,
            fileSizeText: preferred.fileSizeText ?? fallback.fileSizeText,
            resolutionText: preferred.resolutionText ?? fallback.resolutionText,
            postedText: preferred.postedText ?? fallback.postedText,
            updatedText: preferred.updatedText ?? fallback.updatedText,
            favoritesText: preferred.favoritesText ?? fallback.favoritesText,
            subscriptionsText: preferred.subscriptionsText ?? fallback.subscriptionsText,
            scoreText: preferred.scoreText ?? fallback.scoreText,
            lifetimeFavoritesText: preferred.lifetimeFavoritesText ?? fallback.lifetimeFavoritesText,
            lifetimeSubscriptionsText: preferred.lifetimeSubscriptionsText ?? fallback.lifetimeSubscriptionsText,
            visibilityText: preferred.visibilityText ?? fallback.visibilityText,
            moderationText: preferred.moderationText ?? fallback.moderationText,
            detailFields: preferred.detailFields.isEmpty ? fallback.detailFields : preferred.detailFields,
            detailURL: preferred.detailURL
        )
    }

    private static func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Steam 页面请求失败，HTTP \(http.statusCode)：\(url.absoluteString)"
                ]
            )
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
        let authorWorkshopURL = normalizedAuthorWorkshopURL(
            firstURLMatch(
                pattern: #"https://steamcommunity\.com/(?:profiles/\d+|id/[^/"?]+)/myworkshopfiles/(?:\?[^"'\\<]*)?"#,
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
        return SteamWorkshopDetailParseResult(
            title: normalizeText(title),
            author: normalizeAuthorName(author),
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL,
            summary: normalizeText(summary),
            descriptionText: normalizeText(descriptionText),
            tags: tags.map(normalizeText),
            workshopTypeText: normalizedWorkshopTagValue(forKey: "Type", in: workshopTags)
                ?? normalizedStatValue(forKey: "Type", in: stats),
            ageRatingText: normalizedWorkshopTagValue(forKey: "Age Rating", in: workshopTags),
            genreText: normalizedWorkshopTagValue(forKey: "Genre", in: workshopTags),
            categoryText: normalizedWorkshopTagValue(forKey: "Category", in: workshopTags),
            previewImageURL: previewImageURL,
            previewVideoURL: nil,
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

    private static func normalizedAuthorWorkshopURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let absoluteURL = url.absoluteURL
        guard absoluteURL.path.contains("/myworkshopfiles") else { return absoluteURL }
        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            return absoluteURL
        }

        var queryItems = (components.queryItems ?? []).filter { $0.name != "appid" }
        queryItems.append(URLQueryItem(name: "appid", value: Constants.workshopAppID))
        components.queryItems = queryItems
        return components.url ?? absoluteURL
    }

    private static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? {
        if let authorWorkshopURL = normalizedAuthorWorkshopURL(item.authorWorkshopURL) {
            return authorWorkshopURL
        }
        guard let authorProfileURL = item.authorProfileURL else { return nil }
        if authorProfileURL.path.contains("/myworkshopfiles") {
            return normalizedAuthorWorkshopURL(authorProfileURL) ?? authorProfileURL
        }
        guard var components = URLComponents(
            url: authorProfileURL.appendingPathComponent("myworkshopfiles"),
            resolvingAgainstBaseURL: false
        ) else {
            return authorProfileURL
        }
        components.queryItems = [URLQueryItem(name: "appid", value: Constants.workshopAppID)]
        return components.url ?? authorProfileURL
    }

    private static func browsePageHasMore(html: String, currentPage: Int) -> Bool {
        let nextPage = currentPage + 1
        let pattern = #"href\s*=\s*["'][^"']*[?&]p=\#(nextPage)(?:[&#][^"']*|[^"']*)?["']"#
        return firstCapture(pattern: pattern, in: html) != nil
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
            let authorWorkshopURL = normalizedAuthorWorkshopURL(
                firstURLMatch(
                    pattern: #"<a[^>]*class="workshop_author_link"[^>]*href="([^"]+)""#,
                    in: block
                )
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
                    authorWorkshopURL: authorWorkshopURL,
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
        if item.previewAssetKind != .unknown {
            return item
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
            previewAssetKind: previewKind,
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

    private static func fallbackBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: stub.id,
            title: normalizedStubTitle(stub),
            author: normalizedStubAuthor(stub),
            authorProfileURL: stub.authorProfileURL,
            authorWorkshopURL: stub.authorWorkshopURL,
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
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: makeDetailURL(id: stub.id)
        )
    }

    private static func seededBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        guard let cached = loadDetailCache(id: stub.id) else {
            return fallbackBrowserItem(from: stub)
        }
        return mergeStub(stub, into: cached)
    }

    private static func mergeStub(_ stub: SteamWorkshopBrowseStub, into item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title.isEmpty ? normalizedStubTitle(stub) : item.title,
            author: item.author.isEmpty ? normalizedStubAuthor(stub) : item.author,
            authorProfileURL: item.authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL ?? stub.authorWorkshopURL,
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
            lifetimeFavoritesText: item.lifetimeFavoritesText,
            lifetimeSubscriptionsText: item.lifetimeSubscriptionsText,
            visibilityText: item.visibilityText,
            moderationText: item.moderationText,
            detailFields: item.detailFields,
            detailURL: item.detailURL
        )
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

    private static func applyingCachedAuthorNameIfPossible(to item: SteamWorkshopBrowserItem) async -> SteamWorkshopBrowserItem {
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

    private static func resolvedAuthorName(
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

    private static func saveAuthorNameIfPossible(
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

    private static func authorCacheKeys(
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

    private static func creatorID(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.absoluteURL.pathComponents
        guard let profilesIndex = components.firstIndex(of: "profiles"),
              components.indices.contains(profilesIndex + 1) else {
            return nil
        }
        let candidate = components[profilesIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return candidate.isEmpty ? nil : candidate
    }

    private static func normalizedStubTitle(_ stub: SteamWorkshopBrowseStub) -> String {
        let title = stub.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Workshop #\(stub.id)" : title
    }

    private static func normalizedStubAuthor(_ stub: SteamWorkshopBrowseStub) -> String {
        let author = normalizeAuthorName(stub.author ?? "")
        return author.isEmpty ? "未知作者" : author
    }

    private static func formatSteamTimestamp(_ timestamp: Int64?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        return DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            dateStyle: .medium,
            timeStyle: .none
        )
    }

    private static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func buildOfficialDetailFields(
        fileSizeText: String?,
        resolutionText: String?,
        postedText: String?,
        updatedText: String?,
        subscriptionsText: String?,
        favoritesText: String?,
        lifetimeSubscriptionsText: String?,
        lifetimeFavoritesText: String?,
        visibilityText: String?,
        moderationText: String?,
        tags: [String]
    ) -> [SteamWorkshopDetailField] {
        var fields: [SteamWorkshopDetailField] = []

        func appendField(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(SteamWorkshopDetailField(label: label, value: value))
        }

        appendField("File Size", fileSizeText)
        appendField("Resolution", resolutionText)
        appendField("Posted", postedText)
        appendField("Updated", updatedText)
        appendField("Subscriptions", subscriptionsText)
        appendField("Favorited", favoritesText)
        appendField("Lifetime Subscriptions", lifetimeSubscriptionsText)
        appendField("Lifetime Favorited", lifetimeFavoritesText)
        appendField("Visibility", visibilityText)
        appendField("Moderation", moderationText)
        if !tags.isEmpty {
            appendField("Tags", tags.joined(separator: " · "))
        }
        return fields
    }

    private static func visibilityText(for visibility: Int?) -> String? {
        guard let visibility else { return nil }
        switch visibility {
        case 0: return "公开"
        case 1: return "好友可见"
        case 2: return "私有"
        case 3: return "未列出"
        default: return "可见性 \(visibility)"
        }
    }

    private static func moderationText(banned: Int?, banReason: String?) -> String? {
        guard let banned else { return nil }
        if banned == 0 {
            return "正常"
        }
        let reason = normalizeText(banReason ?? "")
        return reason.isEmpty ? "已封禁" : "已封禁 · \(reason)"
    }

    private static func preferredTag(in tags: [String], matching candidates: [String]) -> String? {
        tags.first { tag in
            candidates.contains { candidate in
                tag.compare(candidate, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    private static func isResolutionTag(_ tag: String) -> Bool {
        tag.range(of: #"\d{3,5}\s*x\s*\d{3,5}"#, options: [.regularExpression, .caseInsensitive]) != nil
            || tag.range(of: #"\d{3,5}\s*×\s*\d{3,5}"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isSystemWorkshopTag(_ tag: String) -> Bool {
        if preferredTag(in: [tag], matching: ["Video"]) != nil {
            return true
        }
        if preferredTag(in: [tag], matching: SteamWorkshopAgeRatingFilter.allCases.map(\.rawValue)) != nil {
            return true
        }
        if preferredTag(in: [tag], matching: SteamWorkshopCategoryFilter.allCases.dropFirst().map(\.rawValue)) != nil {
            return true
        }
        return isResolutionTag(tag)
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
