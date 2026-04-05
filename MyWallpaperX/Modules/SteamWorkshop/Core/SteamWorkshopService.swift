//
//  SteamWorkshopService.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Combine
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
        static let detailHydrationExpandedBatchSize = 6
        static let detailHydrationExpandedThreshold = 18
        static let detailHydrationNormalThreshold = 8
        static let detailHydrationInterBatchDelayNanoseconds: UInt64 = 1_300_000_000
        static let detailHydrationFastInterBatchDelayNanoseconds: UInt64 = 450_000_000
        static let detailHydrationNormalInterBatchDelayNanoseconds: UInt64 = 800_000_000
        static let detailPrefetchBatchSize = 2
        static let detailPrefetchInterBatchDelayNanoseconds: UInt64 = 2_000_000_000
        static let browserInteractionDeferralInterval: TimeInterval = 1.2
        static let detailRequestDeferralInterval: TimeInterval = 4.0
        static let browserDebugLoggingEnabledKey = "SteamWorkshop.browserDebugLoggingEnabled"
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
    @Published var downloads: [SteamWorkshopDownloadRecord] = [] {
        didSet { refreshDisplayedDownloads() }
    }
    @Published private(set) var displayedDownloads: [SteamWorkshopDownloadRecord] = []
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
    @Published var downloadsQuery: String = "" {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var downloadsSortMode: SteamWorkshopDownloadsSortMode = .updatedAt {
        didSet { refreshDisplayedDownloads() }
    }
    @Published var downloadsSortAscending: Bool = false {
        didSet { refreshDisplayedDownloads() }
    }
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
    private var lastPreviewPrefetchIDSet = Set<String>()
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
        refreshDisplayedDownloads()
        fetchBrowserItems()
    }

    private func refreshDisplayedDownloads() {
        let nextDisplayedDownloads = filteredAndSortedDownloads(from: downloads)
        if nextDisplayedDownloads != displayedDownloads {
            displayedDownloads = nextDisplayedDownloads
        }
        sanitizeDownloadSelectionAgainstDisplayedDownloads()
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
                } else {
                    self.repairVisibleBrowserItemsIfNeeded()
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
        refreshSelectedBrowserItemDetailIfNeeded(
            forceRefresh: SteamWorkshopDetailRefreshSupport.needsRefresh(resolvedItem)
        )
    }

    func dismissItemDetail() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
    }

    func retryInspectorDetailRefresh(for itemID: String) {
        if let selectedDownloadInspectorItem,
           selectedDownloadInspectorItem.id == itemID {
            retryInspectorPreviewLoad(for: selectedDownloadDetailItem ?? selectedDownloadInspectorItem)
            refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: true)
            return
        }

        guard let selectedBrowserItem, selectedBrowserItem.id == itemID else { return }
        retryInspectorPreviewLoad(for: selectedBrowserItem)
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
    }

    func retrySelectedBrowserItemDetailRefresh() {
        guard let selectedBrowserItem else { return }
        retryInspectorDetailRefresh(for: selectedBrowserItem.id)
    }

    private func retryInspectorPreviewLoad(for item: SteamWorkshopBrowserItem) {
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
            prefetchBrowserPreviewImages(for: cached.items, limit: 24)
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
                    self.prefetchBrowserPreviewImages(for: seededItems, limit: 24)
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
        guard defaults.bool(forKey: Constants.browserDebugLoggingEnabledKey) else { return }
        NSLog("[SteamWorkshopBrowser] %@", message)
    }

    private func detailHydrationDelayNanoseconds(remainingCount: Int) -> UInt64 {
        switch remainingCount {
        case 12...:
            return Constants.detailHydrationFastInterBatchDelayNanoseconds
        case 4...:
            return Constants.detailHydrationNormalInterBatchDelayNanoseconds
        default:
            return Constants.detailHydrationInterBatchDelayNanoseconds
        }
    }

    private func detailHydrationBatchCount(queuedCount: Int) -> Int {
        switch queuedCount {
        case Constants.detailHydrationExpandedThreshold...:
            return Constants.detailHydrationExpandedBatchSize
        case Constants.detailHydrationNormalThreshold...:
            return Constants.detailHydrationBatchSize + 1
        default:
            return Constants.detailHydrationBatchSize
        }
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
        let startIndex = max(0, firstVisibleIndex - 12)
        let endIndex = min(items.count - 1, lastVisibleIndex + 24)
        guard startIndex <= endIndex else { return }
        prefetchBrowserPreviewImages(for: Array(items[startIndex...endIndex]), limit: 36)
    }

    private func prefetchBrowserPreviewImages(for items: [SteamWorkshopBrowserItem], limit: Int) {
        guard !items.isEmpty, limit > 0 else { return }
        let candidates = items.compactMap { item -> (String, URL)? in
            guard let url = item.previewImageURL else { return nil }
            return (item.id, url)
        }
        let limitedCandidates = Array(candidates.prefix(limit))
        let nextIDSet = Set(limitedCandidates.map(\.0))
        let deltaCandidates = limitedCandidates.filter { id, url in
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            let hasCachedImage = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: cacheKey) != nil
            return !lastPreviewPrefetchIDSet.contains(id) || !hasCachedImage
        }
        guard !deltaCandidates.isEmpty else { return }
        lastPreviewPrefetchIDSet = nextIDSet

        for (_, url) in deltaCandidates {
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            SteamWorkshopPreviewImageCache.shared.prefetchImageDataAsync(forKey: cacheKey) {
                await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                    from: url,
                    priority: .prefetch
                )
            }
        }
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
            repairVisibleBrowserItemsIfNeeded()
        }
    }

    private func repairVisibleBrowserItemsIfNeeded() {
        guard !browserItems.isEmpty else { return }
        let stubsNeedingHydration = browserItems
            .filter { SteamWorkshopDetailRefreshSupport.needsRefresh($0) }
            .map(SteamWorkshopDetailRefreshSupport.makeStub)
        guard !stubsNeedingHydration.isEmpty else { return }

        logBrowserDebug(
            "repairVisibleBrowserItemsIfNeeded context=\(browseContext.title) count=\(stubsNeedingHydration.count)"
        )
        enqueueBrowserDetailHydration(
            stubs: stubsNeedingHydration,
            context: browseContext,
            navigationVersion: navigationVersion,
            resetQueue: false
        )
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
        lastPreviewPrefetchIDSet.removeAll()
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
                let batchCount = min(
                    self.detailHydrationBatchCount(queuedCount: self.pendingBrowserDetailStubs.count),
                    self.pendingBrowserDetailStubs.count
                )
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
                    self.logBrowserDebug(
                        "detail hydration success batchCount=\(items.count) remainingQueue=\(self.pendingBrowserDetailStubs.count)"
                    )
                }
                let remainingCount = await MainActor.run { self.pendingBrowserDetailStubs.count }
                try? await Task.sleep(nanoseconds: detailHydrationDelayNanoseconds(remainingCount: remainingCount))
            } catch {
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                let isRateLimited = nsError.domain == NSURLErrorDomain && nsError.code == 429
                let isTransientNetworkFailure = nsError.domain == NSURLErrorDomain
                let attempt = await MainActor.run { () -> Int in
                    var highestAttempt = 0
                    for stub in stubs {
                        let next = (self.browserDetailRetryCounts[stub.id] ?? 0) + 1
                        self.browserDetailRetryCounts[stub.id] = next
                        highestAttempt = max(highestAttempt, next)
                    }
                    return highestAttempt
                }

                if isRateLimited, attempt <= 4 {
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

                if isTransientNetworkFailure, attempt <= 2 {
                    await MainActor.run {
                        for stub in stubs {
                            if self.pendingBrowserDetailStubIDs.insert(stub.id).inserted {
                                self.pendingBrowserDetailStubs.append(stub)
                            }
                        }
                        self.logBrowserDebug(
                            "detail hydration transient retry batchCount=\(stubs.count) attempt=\(attempt) queueCount=\(self.pendingBrowserDetailStubs.count) code=\(nsError.code)"
                        )
                    }
                    let backoffSeconds = UInt64(min(8, attempt * 2))
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

    private func refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedBrowserItem else { return }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedBrowserItem = true
        selectedBrowserItemError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)

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
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedDownloadDetailItem = true
        selectedDownloadDetailError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)

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
            }
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

}
