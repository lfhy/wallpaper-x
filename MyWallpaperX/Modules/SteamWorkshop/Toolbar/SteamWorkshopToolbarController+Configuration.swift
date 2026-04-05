//
//  SteamWorkshopToolbarController+Configuration.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
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

    func configureZoomItem() {
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: gridWidth()
        )
        zoomControl.setEnabled(availability.canZoomIn, forSegment: 0)
        zoomControl.setEnabled(availability.canZoomOut, forSegment: 1)
    }

    func configureAuthItems() {
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

    func configureAuthorBackItem() {
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        authorBackToolbarItem.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.alphaValue = isBrowsingAuthorWorkshop ? 1.0 : 0.45
        authorBackButton.toolTip = isBrowsingAuthorWorkshop
            ? "返回 Steam 创意工坊总榜"
            : "当前不在作者工坊模式"
        authorBackToolbarItem.toolTip = authorBackButton.toolTip
    }

    func configureRefreshItem() {
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

    func syncSortPopup() {
        let allSources = SteamWorkshopSource.allCases
        sortPopupButton.selectItem(at: allSources.firstIndex(of: SteamWorkshopService.shared.source) ?? 0)
        let isEnabled = !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        sortToolbarItem.isEnabled = isEnabled
        sortPopupButton.isEnabled = isEnabled
    }

    func syncTrendingWindowPopup() {
        let allWindows = SteamWorkshopTrendingWindow.allCases
        trendingWindowPopupButton.selectItem(at: allWindows.firstIndex(of: SteamWorkshopService.shared.trendingWindow) ?? 0)
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowPopupButton.isEnabled = isEnabled
    }

    func configureFilterItem() {
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

    func syncSearchField() {
        searchToolbarItem.searchField.stringValue = SteamWorkshopService.shared.browserQuery
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        searchToolbarItem.isEnabled = true
        searchToolbarItem.searchField.isEnabled = true
        searchToolbarItem.searchField.placeholderString = isBrowsingAuthorWorkshop
            ? "搜索当前作者作品"
            : "搜索 Steam 视频"
    }

    func syncBrowserContextControls() {
        guard isSteamWorkshopMode, !isDownloadsMode else { return }
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        configureAuthorBackItem()
        syncSortPopup()
        syncTrendingWindowPopup()
        configureFilterItem()
        syncSearchField()
        refreshToolbarContextViews()
    }

    func refreshToolbarContextViews() {
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

    func syncDownloadsSearchField() {
        downloadsSearchItem.searchField.stringValue = SteamWorkshopService.shared.downloadsQuery
    }

    func configureDownloadsTitleItem() {
        downloadsTitleLabel.stringValue = Title.downloads
        downloadsTitleItem.toolTip = Title.downloads
    }

    func configureDownloadsSelectItem() {
        let isMultiSelectMode = SteamWorkshopService.shared.isDownloadsMultiSelectMode
        let symbolName = isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
        downloadsSelectItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "选择")
        downloadsSelectItem.toolTip = isMultiSelectMode ? "退出选择模式" : "进入选择模式"
    }

    func configureDownloadsDeleteItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canDeleteSelectedDownload
        downloadsDeleteItem.isEnabled = enabled
        downloadsDeleteItem.toolTip = enabled
            ? "删除当前选中的下载项"
            : "请先选中一个已下载或失败的项目"
    }

    func configureDownloadsInfoItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canShowSelectedDownloadInfo
        downloadsInfoItem.isEnabled = enabled
        downloadsInfoItem.toolTip = enabled
            ? "查看当前选中下载项的详细信息"
            : "请先单选一个下载项"
    }

    func configureDownloadsRevealItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canRevealSelectedDownload
        downloadsRevealItem.isEnabled = enabled
        downloadsRevealItem.toolTip = enabled
            ? "在访达中显示当前选中的下载项"
            : "请先单选一个下载项"
    }

    func configureDownloadsSortItem() {
        let service = SteamWorkshopService.shared
        let direction = service.downloadsSortAscending ? "升序" : "降序"
        downloadsSortMenuButton.toolTip = "排序方式：\(service.downloadsSortMode.displayName) · \(direction)"
        downloadsSortItem.toolTip = downloadsSortMenuButton.toolTip
    }
}
