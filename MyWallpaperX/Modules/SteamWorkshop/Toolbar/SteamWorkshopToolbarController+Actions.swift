//
//  SteamWorkshopToolbarController+Actions.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    @objc func handleSortAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let sources = SteamWorkshopSource.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < sources.count else { return }
        SteamWorkshopService.shared.source = sources[sender.indexOfSelectedItem]
        syncTrendingWindowPopup()
    }

    @objc func handleTrendingWindowAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let windows = SteamWorkshopTrendingWindow.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < windows.count else { return }
        SteamWorkshopService.shared.trendingWindow = windows[sender.indexOfSelectedItem]
    }

    @objc func handleRefresh() {
        SteamWorkshopService.shared.refresh()
    }

    @objc func handleBackToDiscovery() {
        SteamWorkshopService.shared.returnToDiscoveryBrowse()
    }

    @objc func handleAccountMenu() {
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

    @objc func handleFilterMenu() {
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

    @objc func handlePresentLogin() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.presentLoginGate()
        }
    }

    @objc func handleLogout() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.logout()
        }
    }

    @objc func handleRevealDownloads() {
        SteamWorkshopService.shared.revealSelectedDownload()
        configureDownloadsRevealItem()
    }

    @objc func handleDeleteSelectedDownload() {
        SteamWorkshopService.shared.deleteSelectedDownload()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc func handleToggleDownloadsSelectMode() {
        SteamWorkshopService.shared.toggleDownloadsMultiSelectMode()
        configureDownloadsSelectItem()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc func handleShowSelectedDownloadInfo() {
        SteamWorkshopService.shared.presentSelectedDownloadInfo()
        configureDownloadsInfoItem()
    }

    @objc func handleDownloadsSortAction(_ sender: NSButton) {
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

    @objc func handleDownloadsSortModeItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SteamWorkshopDownloadsSortMode(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.downloadsSortMode = mode
        configureDownloadsSortItem()
    }

    @objc func handleDownloadsSortDirectionItem(_ sender: NSMenuItem) {
        guard let ascending = sender.representedObject as? Bool else { return }
        SteamWorkshopService.shared.downloadsSortAscending = ascending
        configureDownloadsSortItem()
    }

    @objc func handleBrowseAnonymously() {
        DispatchQueue.main.async {
            SteamWorkshopService.shared.browseAnonymously()
        }
    }

    @objc func handleThemeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopThemeFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.themeFilter = filter
        configureFilterItem()
    }

    @objc func handleAgeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopAgeRatingFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.ageRatingFilter = filter
        configureFilterItem()
    }

    @objc func handleResolutionFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopResolutionFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.resolutionFilter = filter
        configureFilterItem()
    }

    @objc func handleClearFilters() {
        SteamWorkshopService.shared.clearFilters()
        configureFilterItem()
    }

    @objc func handleCategoryFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopCategoryFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.categoryFilter = filter
        configureFilterItem()
    }

    @objc func handleZoomAction(_ sender: NSSegmentedControl) {
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
