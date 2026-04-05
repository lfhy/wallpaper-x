//
//  SteamWorkshopToolbarController.swift
//  MyWallpaperX
//

import AppKit
import Combine

extension NSToolbarItem.Identifier {
    static let steamAuthorBack = NSToolbarItem.Identifier("ToolbarSteamAuthorBack")
    static let steamSort = NSToolbarItem.Identifier("ToolbarSteamSort")
    static let steamTrendingWindow = NSToolbarItem.Identifier("ToolbarSteamTrendingWindow")
    static let steamFilter = NSToolbarItem.Identifier("ToolbarSteamFilter")
    static let steamAccount = NSToolbarItem.Identifier("ToolbarSteamAccount")
    static let steamRefresh = NSToolbarItem.Identifier("ToolbarSteamRefresh")
    static let steamZoom = NSToolbarItem.Identifier("ToolbarSteamZoom")
    static let steamSearch = NSToolbarItem.Identifier("ToolbarSteamSearch")
    static let steamDownloadsTitle = NSToolbarItem.Identifier("ToolbarSteamDownloadsTitle")
    static let steamDownloadsReveal = NSToolbarItem.Identifier("ToolbarSteamDownloadsReveal")
    static let steamDownloadsSelect = NSToolbarItem.Identifier("ToolbarSteamDownloadsSelect")
    static let steamDownloadsDelete = NSToolbarItem.Identifier("ToolbarSteamDownloadsDelete")
    static let steamDownloadsInfo = NSToolbarItem.Identifier("ToolbarSteamDownloadsInfo")
    static let steamDownloadsSort = NSToolbarItem.Identifier("ToolbarSteamDownloadsSort")
    static let steamDownloadsSearch = NSToolbarItem.Identifier("ToolbarSteamDownloadsSearch")
}

final class SteamWorkshopToolbarController: NSObject, NSSearchFieldDelegate {
    private enum Title {
        static let browser = "Steam 创意工坊"
        static let downloads = "Steam 下载"
    }

    weak var toolbar: NSToolbar?
    weak var window: NSWindow?
    var localModeIdentifiers: [NSToolbarItem.Identifier] = []
    var titleUpdateHandler: ((String) -> Void)?

    private(set) var isSteamWorkshopMode = false
    private var isDownloadsMode = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private let discoveryBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAccount,
        .space,
        .steamRefresh,
        .space,
        .steamSort,
        .space,
        .steamTrendingWindow,
        .space,
        .steamFilter,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    private let authorWorkshopBrowserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamAuthorBack,
        .space,
        .steamAccount,
        .space,
        .steamRefresh,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    var browserIdentifiers: [NSToolbarItem.Identifier] {
        SteamWorkshopService.shared.isBrowsingAuthorWorkshop
            ? authorWorkshopBrowserIdentifiers
            : discoveryBrowserIdentifiers
    }

    let downloadsIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        .steamDownloadsTitle,
        .flexibleSpace,
        .steamDownloadsSelect,
        .space,
        .steamDownloadsDelete,
        .steamDownloadsInfo,
        .steamDownloadsReveal,
        .steamDownloadsSort,
        .space,
        .steamZoom,
        .space,
        .steamDownloadsSearch
    ]

    init(toolbar: NSToolbar, window: NSWindow?) {
        self.toolbar = toolbar
        self.window = window
        super.init()
        installObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func installObservers() {
        let modeObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            let isDownloads = notification.userInfo?["isDownloads"] as? Bool ?? false
            self?.switchMode(enabled: enabled, isDownloads: isDownloads)
        }
        observers.append(modeObserver)

        let browseContextObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopBrowseContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncBrowserContextControls()
        }
        observers.append(browseContextObserver)

        SteamWorkshopService.shared.$zoomOffset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureZoomItem()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            SteamWorkshopService.shared.$requiresLogin,
            SteamWorkshopService.shared.$isAnonymousBrowsing
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.configureAuthItems()
        }
        .store(in: &cancellables)

        SteamWorkshopService.shared.$isPreparingRuntime
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.configureAuthItems()
        }
        .store(in: &cancellables)

        SteamWorkshopService.shared.$source
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSortPopup()
                self?.syncTrendingWindowPopup()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$trendingWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTrendingWindowPopup()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$browserSectionTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode else { return }
                self.titleUpdateHandler?(title)
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$isRefreshingBrowserFeed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureRefreshItem()
            }
            .store(in: &cancellables)

        SteamWorkshopService.shared.$isBrowsingAuthorWorkshop
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBrowserContextControls()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            SteamWorkshopService.shared.$selectedDownloadID,
            SteamWorkshopService.shared.$downloads
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.configureDownloadsInfoItem()
            self?.configureDownloadsRevealItem()
            self?.configureDownloadsDeleteItem()
        }
        .store(in: &cancellables)

        SteamWorkshopService.shared.$isDownloadsMultiSelectMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureDownloadsSelectItem()
                self?.configureDownloadsInfoItem()
                self?.configureDownloadsRevealItem()
                self?.configureDownloadsDeleteItem()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            SteamWorkshopService.shared.$downloadsSortMode,
            SteamWorkshopService.shared.$downloadsSortAscending
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.configureDownloadsSortItem()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            SteamWorkshopService.shared.$themeFilter,
            SteamWorkshopService.shared.$ageRatingFilter,
            SteamWorkshopService.shared.$resolutionFilter,
            SteamWorkshopService.shared.$categoryFilter
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.configureFilterItem()
        }
        .store(in: &cancellables)
    }

    private func switchMode(enabled: Bool, isDownloads: Bool) {
        guard enabled else {
            isSteamWorkshopMode = false
            isDownloadsMode = false
            return
        }
        isSteamWorkshopMode = true
        isDownloadsMode = isDownloads

        if isDownloads {
            configureDownloadsTitleItem()
            configureDownloadsSelectItem()
            configureDownloadsDeleteItem()
            configureDownloadsInfoItem()
            configureDownloadsRevealItem()
            configureDownloadsSortItem()
            syncDownloadsSearchField()
        } else {
            titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
            syncBrowserContextControls()
            configureAuthItems()
            configureRefreshItem()
        }
        configureZoomItem()
    }

    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .steamAuthorBack:
            configureAuthorBackItem()
            return authorBackToolbarItem
        case .steamSort:
            syncSortPopup()
            return sortToolbarItem
        case .steamTrendingWindow:
            syncTrendingWindowPopup()
            return trendingWindowToolbarItem
        case .steamFilter:
            configureFilterItem()
            return filterToolbarItem
        case .steamAccount: return accountToolbarItem
        case .steamRefresh: return refreshToolbarItem
        case .steamZoom: return zoomToolbarItem
        case .steamSearch:
            syncSearchField()
            return searchToolbarItem
        case .steamDownloadsTitle: return downloadsTitleItem
        case .steamDownloadsReveal: return downloadsRevealItem
        case .steamDownloadsSelect:
            configureDownloadsSelectItem()
            return downloadsSelectItem
        case .steamDownloadsDelete:
            configureDownloadsDeleteItem()
            return downloadsDeleteItem
        case .steamDownloadsInfo:
            configureDownloadsInfoItem()
            return downloadsInfoItem
        case .steamDownloadsSort:
            configureDownloadsSortItem()
            return downloadsSortItem
        case .steamDownloadsSearch: return downloadsSearchItem
        default: return nil
        }
    }

    lazy var downloadsTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: Title.downloads)
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var downloadsTitleContainer: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(downloadsTitleLabel)
        NSLayoutConstraint.activate([
            downloadsTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            downloadsTitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            downloadsTitleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var downloadsTitleItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsTitle)
        item.label = "当前目录"
        item.paletteLabel = "当前目录"
        item.autovalidates = false
        item.isBordered = false
        item.view = downloadsTitleContainer
        return item
    }()

    lazy var downloadsRevealItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsReveal)
        item.label = "查看文件"
        item.paletteLabel = "查看文件"
        item.toolTip = "在访达中显示当前选中的下载项"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "查看文件")
        item.target = self
        item.action = #selector(handleRevealDownloads)
        return item
    }()

    lazy var downloadsDeleteItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsDelete)
        item.label = "删除"
        item.paletteLabel = "删除"
        item.toolTip = "删除当前选中的下载项"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        item.target = self
        item.action = #selector(handleDeleteSelectedDownload)
        return item
    }()

    lazy var downloadsInfoItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsInfo)
        item.label = "信息"
        item.paletteLabel = "信息"
        item.toolTip = "查看详细信息"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "信息")
        item.target = self
        item.action = #selector(handleShowSelectedDownloadInfo)
        return item
    }()

    lazy var downloadsSelectItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsSelect)
        item.label = "选择"
        item.paletteLabel = "选择"
        item.toolTip = "进入选择模式"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "选择")
        item.target = self
        item.action = #selector(handleToggleDownloadsSelectMode)
        return item
    }()

    lazy var downloadsSearchItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .steamDownloadsSearch)
        item.searchField.delegate = self
        item.searchField.placeholderString = "搜索下载项"
        item.searchField.sendsSearchStringImmediately = true
        item.resignsFirstResponderWithCancel = true
        item.preferredWidthForSearchField = 165
        return item
    }()

    lazy var downloadsSortMenuButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleDownloadsSortAction(_:))
        button.toolTip = "排序方式"
        return button
    }()

    lazy var downloadsSortItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsSort)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.toolTip = "排序方式"
        item.autovalidates = false
        item.view = downloadsSortMenuButton
        return item
    }()

    lazy var zoomControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大") ?? NSImage()
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(handleZoomAction(_:))
        )
        control.segmentStyle = .capsule
        control.setWidth(28, forSegment: 0)
        control.setWidth(28, forSegment: 1)
        return control
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamZoom)
        item.label = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip = "调整 Steam 条目卡片大小"
        item.autovalidates = false
        item.view = zoomControl
        return item
    }()

    lazy var authorBackButton: NSButton = {
        let button = NSButton(title: "返回总榜", target: self, action: #selector(handleBackToDiscovery))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "返回总榜")
        button.imagePosition = .imageLeading
        return button
    }()

    lazy var authorBackToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamAuthorBack)
        item.label = "返回总榜"
        item.paletteLabel = "返回总榜"
        item.toolTip = "从作者工坊返回 Steam 创意工坊总榜"
        item.autovalidates = false
        item.view = authorBackButton
        return item
    }()

    lazy var sortPopupButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 118, height: 30), pullsDown: false)
        button.target = self
        button.action = #selector(handleSortAction(_:))
        SteamWorkshopSource.allCases.forEach { source in
            button.menu?.addItem(withTitle: source.displayName, action: nil, keyEquivalent: "")
        }
        return button
    }()

    lazy var sortToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamSort)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.toolTip = "切换 Steam 创意工坊排序方式"
        item.autovalidates = false
        item.view = sortPopupButton
        return item
    }()

    lazy var trendingWindowPopupButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 102, height: 30), pullsDown: false)
        button.target = self
        button.action = #selector(handleTrendingWindowAction(_:))
        SteamWorkshopTrendingWindow.allCases.forEach { window in
            button.menu?.addItem(withTitle: window.displayName, action: nil, keyEquivalent: "")
        }
        return button
    }()

    lazy var trendingWindowToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamTrendingWindow)
        item.label = "时间段"
        item.paletteLabel = "时间段"
        item.toolTip = "切换最热门榜单的时间范围"
        item.autovalidates = false
        item.view = trendingWindowPopupButton
        return item
    }()

    lazy var filterButton: NSButton = {
        let button = NSButton(title: "筛选", target: self, action: #selector(handleFilterMenu))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "筛选")
        button.imagePosition = .imageLeading
        return button
    }()

    lazy var filterToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamFilter)
        item.label = "筛选"
        item.paletteLabel = "筛选"
        item.toolTip = "选择类型、年龄分级和分辨率筛选规则"
        item.autovalidates = false
        item.view = filterButton
        return item
    }()

    lazy var searchToolbarItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .steamSearch)
        item.searchField.delegate = self
        item.searchField.placeholderString = "搜索 Steam 视频"
        item.searchField.sendsSearchStringImmediately = true
        item.resignsFirstResponderWithCancel = true
        item.preferredWidthForSearchField = 180
        return item
    }()

    lazy var refreshToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamRefresh)
        item.label = "刷新"
        item.paletteLabel = "刷新"
        item.toolTip = "刷新 Steam 创意工坊列表"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        item.target = self
        item.action = #selector(handleRefresh)
        return item
    }()

    lazy var accountButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleAccountMenu)
        return button
    }()

    lazy var accountToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamAccount)
        item.label = "账号"
        item.paletteLabel = "Steam 账号"
        item.toolTip = "打开 Steam 登录页"
        item.autovalidates = false
        item.view = accountButton
        return item
    }()

    func focusSearch() {
        guard isSteamWorkshopMode else { return }
        if isDownloadsMode {
            window?.makeFirstResponder(downloadsSearchItem.searchField)
        } else {
            window?.makeFirstResponder(searchToolbarItem.searchField)
        }
    }

    func performZoom(delta: Int) {
        guard isSteamWorkshopMode else { return }
        let width = gridWidth()
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: width
        )
        let canZoom = delta > 0 ? availability.canZoomIn : availability.canZoomOut
        guard canZoom else { return }
        let segment = delta > 0 ? 0 : 1
        zoomControl.setSelected(true, forSegment: segment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.zoomControl.setSelected(false, forSegment: segment)
        }
        SteamWorkshopService.shared.zoomOffset += delta
        configureZoomItem()
    }

    private func gridWidth() -> CGFloat {
        (window?.contentView?.bounds.width ?? 800) - 220
    }

    private func configureZoomItem() {
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: gridWidth()
        )
        zoomControl.setEnabled(availability.canZoomIn, forSegment: 0)
        zoomControl.setEnabled(availability.canZoomOut, forSegment: 1)
    }

    private func configureAuthItems() {
        let service = SteamWorkshopService.shared
        let isAuthenticated = !service.requiresLogin && !service.isAnonymousBrowsing
        let isBusy = service.isPreparingRuntime || service.isAuthenticating

        let symbolName: String
        if service.isPreparingRuntime {
            symbolName = "hourglass.circle"
        } else if isAuthenticated {
            symbolName = "person.crop.circle.badge.checkmark"
        } else {
            symbolName = "person.crop.circle"
        }
        accountButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Steam 账号")
        accountButton.contentTintColor = isAuthenticated ? .controlAccentColor : .labelColor
        accountButton.toolTip = isAuthenticated ? "Steam 账号菜单" : "登录或匿名浏览"
        accountButton.isEnabled = !isBusy
        accountToolbarItem.toolTip = accountButton.toolTip
    }

    private func configureAuthorBackItem() {
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        authorBackToolbarItem.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.alphaValue = isBrowsingAuthorWorkshop ? 1.0 : 0.45
        authorBackButton.toolTip = isBrowsingAuthorWorkshop
            ? "返回 Steam 创意工坊总榜"
            : "当前不在作者工坊模式"
        authorBackToolbarItem.toolTip = authorBackButton.toolTip
    }

    private func configureRefreshItem() {
        let service = SteamWorkshopService.shared
        let isRefreshing = service.isRefreshingBrowserFeed
        refreshToolbarItem.isEnabled = !isDownloadsMode && !isRefreshing
        refreshToolbarItem.image = NSImage(
            systemSymbolName: isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise",
            accessibilityDescription: "刷新"
        )
        refreshToolbarItem.toolTip = isRefreshing
            ? (service.isBrowsingAuthorWorkshop ? "正在刷新作者工坊列表…" : "正在刷新 Steam 创意工坊列表…")
            : "刷新 Steam 创意工坊列表"
    }

    private func syncSortPopup() {
        let allSources = SteamWorkshopSource.allCases
        sortPopupButton.selectItem(at: allSources.firstIndex(of: SteamWorkshopService.shared.source) ?? 0)
        let isEnabled = !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        sortToolbarItem.isEnabled = isEnabled
        sortPopupButton.isEnabled = isEnabled
    }

    private func syncTrendingWindowPopup() {
        let allWindows = SteamWorkshopTrendingWindow.allCases
        trendingWindowPopupButton.selectItem(at: allWindows.firstIndex(of: SteamWorkshopService.shared.trendingWindow) ?? 0)
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowPopupButton.isEnabled = isEnabled
    }

    private func configureFilterItem() {
        let service = SteamWorkshopService.shared
        let selectedCount = service.activeFilterDisplayParts.count
        filterButton.title = selectedCount == 0 ? "筛选" : "筛选 \(selectedCount)"
        let isEnabled = !service.isBrowsingAuthorWorkshop
        filterButton.toolTip = service.isBrowsingAuthorWorkshop
            ? "作者工坊模式暂不支持排序筛选"
            : "当前筛选：\(service.activeFilterSummary)"
        filterToolbarItem.isEnabled = isEnabled
        filterButton.isEnabled = isEnabled
        filterToolbarItem.toolTip = filterButton.toolTip
    }

    private func syncSearchField() {
        searchToolbarItem.searchField.stringValue = SteamWorkshopService.shared.browserQuery
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        searchToolbarItem.isEnabled = true
        searchToolbarItem.searchField.isEnabled = true
        searchToolbarItem.searchField.placeholderString = isBrowsingAuthorWorkshop
            ? "搜索当前作者作品"
            : "搜索 Steam 视频"
    }

    private func syncBrowserContextControls() {
        guard isSteamWorkshopMode, !isDownloadsMode else { return }
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        configureAuthorBackItem()
        syncSortPopup()
        syncTrendingWindowPopup()
        configureFilterItem()
        syncSearchField()
        refreshToolbarContextViews()
    }

    private func refreshToolbarContextViews() {
        let views: [NSView] = [
            authorBackButton,
            sortPopupButton,
            trendingWindowPopupButton,
            filterButton,
            searchToolbarItem.searchField
        ]
        views.forEach {
            $0.needsLayout = true
            $0.needsDisplay = true
            $0.displayIfNeeded()
        }
        toolbar?.items.forEach { item in
            item.view?.needsLayout = true
            item.view?.needsDisplay = true
        }
    }

    private func syncDownloadsSearchField() {
        downloadsSearchItem.searchField.stringValue = SteamWorkshopService.shared.downloadsQuery
    }

    private func configureDownloadsTitleItem() {
        downloadsTitleLabel.stringValue = Title.downloads
        downloadsTitleItem.toolTip = Title.downloads
    }

    private func configureDownloadsSelectItem() {
        let isMultiSelectMode = SteamWorkshopService.shared.isDownloadsMultiSelectMode
        let symbolName = isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
        downloadsSelectItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "选择")
        downloadsSelectItem.toolTip = isMultiSelectMode ? "退出选择模式" : "进入选择模式"
    }

    private func configureDownloadsDeleteItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canDeleteSelectedDownload
        downloadsDeleteItem.isEnabled = enabled
        downloadsDeleteItem.toolTip = enabled
            ? "删除当前选中的下载项"
            : "请先选中一个已下载或失败的项目"
    }

    private func configureDownloadsInfoItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canShowSelectedDownloadInfo
        downloadsInfoItem.isEnabled = enabled
        downloadsInfoItem.toolTip = enabled
            ? "查看当前选中下载项的详细信息"
            : "请先单选一个下载项"
    }

    private func configureDownloadsRevealItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canRevealSelectedDownload
        downloadsRevealItem.isEnabled = enabled
        downloadsRevealItem.toolTip = enabled
            ? "在访达中显示当前选中的下载项"
            : "请先单选一个下载项"
    }

    private func configureDownloadsSortItem() {
        let service = SteamWorkshopService.shared
        let direction = service.downloadsSortAscending ? "升序" : "降序"
        downloadsSortMenuButton.toolTip = "排序方式：\(service.downloadsSortMode.displayName) · \(direction)"
        downloadsSortItem.toolTip = downloadsSortMenuButton.toolTip
    }

    @objc private func handleSortAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let sources = SteamWorkshopSource.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < sources.count else { return }
        SteamWorkshopService.shared.source = sources[sender.indexOfSelectedItem]
        syncTrendingWindowPopup()
    }

    @objc private func handleTrendingWindowAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let windows = SteamWorkshopTrendingWindow.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < windows.count else { return }
        SteamWorkshopService.shared.trendingWindow = windows[sender.indexOfSelectedItem]
    }

    @objc private func handleRefresh() {
        SteamWorkshopService.shared.refresh()
    }

    @objc private func handleBackToDiscovery() {
        SteamWorkshopService.shared.returnToDiscoveryBrowse()
    }

    @objc private func handleAccountMenu() {
        let service = SteamWorkshopService.shared
        let isAuthenticated = !service.requiresLogin && !service.isAnonymousBrowsing

        let menu = NSMenu()
        menu.autoenablesItems = false

        if isAuthenticated {
            let switchItem = NSMenuItem(title: "切换账号", action: #selector(handlePresentLogin), keyEquivalent: "")
            switchItem.target = self
            switchItem.isEnabled = !service.isPreparingRuntime && !service.isAuthenticating
            menu.addItem(switchItem)

            let logoutItem = NSMenuItem(title: "退出登录", action: #selector(handleLogout), keyEquivalent: "")
            logoutItem.target = self
            logoutItem.isEnabled = !service.isPreparingRuntime && !service.isAuthenticating
            menu.addItem(logoutItem)
        } else {
            let loginItem = NSMenuItem(title: "登录 Steam", action: #selector(handlePresentLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.isEnabled = !service.isPreparingRuntime && !service.isAuthenticating
            menu.addItem(loginItem)

            let anonymousItem = NSMenuItem(title: "匿名浏览", action: #selector(handleBrowseAnonymously), keyEquivalent: "")
            anonymousItem.target = self
            anonymousItem.isEnabled = !service.isPreparingRuntime && !service.isAuthenticating
            menu.addItem(anonymousItem)
        }

        let buttonBounds = accountButton.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height + 4), in: accountButton)
    }

    @objc private func handleFilterMenu() {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let themeMenuItem = NSMenuItem(title: "类型", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        SteamWorkshopThemeFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleThemeFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.themeFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            themeMenu.addItem(item)
        }
        themeMenuItem.submenu = themeMenu
        menu.addItem(themeMenuItem)

        let ageMenuItem = NSMenuItem(title: "分级", action: nil, keyEquivalent: "")
        let ageMenu = NSMenu()
        SteamWorkshopAgeRatingFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleAgeFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.ageRatingFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            ageMenu.addItem(item)
        }
        ageMenuItem.submenu = ageMenu
        menu.addItem(ageMenuItem)

        let resolutionMenuItem = NSMenuItem(title: "分辨率", action: nil, keyEquivalent: "")
        let resolutionMenu = NSMenu()
        SteamWorkshopResolutionFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleResolutionFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.resolutionFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            resolutionMenu.addItem(item)
        }
        resolutionMenuItem.submenu = resolutionMenu
        menu.addItem(resolutionMenuItem)

        let categoryMenuItem = NSMenuItem(title: "分类", action: nil, keyEquivalent: "")
        let categoryMenu = NSMenu()
        SteamWorkshopCategoryFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleCategoryFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.categoryFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            categoryMenu.addItem(item)
        }
        categoryMenuItem.submenu = categoryMenu
        menu.addItem(categoryMenuItem)

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "清空筛选", action: #selector(handleClearFilters), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = service.activeFilterSummary != "未筛选"
        menu.addItem(clearItem)

        let buttonBounds = filterButton.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height + 4), in: filterButton)
    }

    @objc private func handlePresentLogin() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.presentLoginGate()
        }
    }

    @objc private func handleLogout() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.logout()
        }
    }

    @objc private func handleRevealDownloads() {
        SteamWorkshopService.shared.revealSelectedDownload()
        configureDownloadsRevealItem()
    }

    @objc private func handleDeleteSelectedDownload() {
        SteamWorkshopService.shared.deleteSelectedDownload()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc private func handleToggleDownloadsSelectMode() {
        SteamWorkshopService.shared.toggleDownloadsMultiSelectMode()
        configureDownloadsSelectItem()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc private func handleShowSelectedDownloadInfo() {
        SteamWorkshopService.shared.presentSelectedDownloadInfo()
        configureDownloadsInfoItem()
    }

    @objc private func handleDownloadsSortAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        SteamWorkshopDownloadsSortMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.displayName, action: #selector(handleDownloadsSortModeItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = service.downloadsSortMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let ascendingItem = NSMenuItem(title: "升序", action: #selector(handleDownloadsSortDirectionItem(_:)), keyEquivalent: "")
        ascendingItem.target = self
        ascendingItem.representedObject = true
        ascendingItem.state = service.downloadsSortAscending ? .on : .off
        menu.addItem(ascendingItem)

        let descendingItem = NSMenuItem(title: "降序", action: #selector(handleDownloadsSortDirectionItem(_:)), keyEquivalent: "")
        descendingItem.target = self
        descendingItem.representedObject = false
        descendingItem.state = service.downloadsSortAscending ? .off : .on
        menu.addItem(descendingItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func handleDownloadsSortModeItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SteamWorkshopDownloadsSortMode(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.downloadsSortMode = mode
        configureDownloadsSortItem()
    }

    @objc private func handleDownloadsSortDirectionItem(_ sender: NSMenuItem) {
        guard let ascending = sender.representedObject as? Bool else { return }
        SteamWorkshopService.shared.downloadsSortAscending = ascending
        configureDownloadsSortItem()
    }

    @objc private func handleBrowseAnonymously() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.browseAnonymously()
        }
    }

    @objc private func handleThemeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopThemeFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.themeFilter = filter
        configureFilterItem()
    }

    @objc private func handleAgeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopAgeRatingFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.ageRatingFilter = filter
        configureFilterItem()
    }

    @objc private func handleResolutionFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopResolutionFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.resolutionFilter = filter
        configureFilterItem()
    }

    @objc private func handleClearFilters() {
        SteamWorkshopService.shared.clearFilters()
        configureFilterItem()
    }

    @objc private func handleCategoryFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopCategoryFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.categoryFilter = filter
        configureFilterItem()
    }

    @objc private func handleZoomAction(_ sender: NSSegmentedControl) {
        performZoom(delta: sender.selectedSegment == 0 ? 1 : -1)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if field === downloadsSearchItem.searchField {
            SteamWorkshopService.shared.downloadsQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        } else {
            SteamWorkshopService.shared.browserQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        }
    }

    var allowedItemIdentifiers: [NSToolbarItem.Identifier] {
        [
            .steamAuthorBack,
            .steamSort,
            .steamTrendingWindow,
            .steamFilter,
            .steamAccount,
            .steamRefresh,
            .steamZoom,
            .steamSearch,
            .steamDownloadsTitle,
            .steamDownloadsSelect,
            .steamDownloadsDelete,
            .steamDownloadsInfo,
            .steamDownloadsReveal,
            .steamDownloadsSort,
            .steamDownloadsSearch,
            .space,
            .flexibleSpace
        ]
    }
}
