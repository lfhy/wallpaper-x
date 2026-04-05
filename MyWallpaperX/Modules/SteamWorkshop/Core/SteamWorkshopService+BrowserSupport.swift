//
//  SteamWorkshopService+BrowserSupport.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    func loadingStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "正在抓取 Wallpaper Engine 创意工坊视频列表…"
        case .authorWorkshop(let authorName, _):
            return "正在抓取 \(authorName) 的创意工坊作品…"
        }
    }

    func cachedStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "已载入缓存的创意工坊列表"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的工坊缓存列表"
        }
    }

    func emptyResultsStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "没有抓取到符合条件的视频项目。"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 当前没有抓取到可展示的视频项目。"
        }
    }

    func baseCardsStatusMessage(for context: SteamWorkshopBrowseContext, count: Int) -> String {
        switch context {
        case .discovery:
            return "已载入 \(count) 张基础卡片，正在补全详情…"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的 \(count) 张基础卡片，正在补全详情…"
        }
    }

    func completedStatusMessage(
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

    func failureStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            return "创意工坊列表抓取失败"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 的工坊列表抓取失败"
        }
    }

    func prefetchStatusMessage(for context: SteamWorkshopBrowseContext, page: Int) -> String {
        switch context {
        case .discovery:
            return "已预加载第 \(page) 页基础卡片，正在补全详细信息…"
        case .authorWorkshop(let authorName, _):
            return "已预加载 \(authorName) 的第 \(page) 页基础卡片，正在补全详细信息…"
        }
    }

    func browsePageSize(for context: SteamWorkshopBrowseContext) -> Int {
        switch context {
        case .discovery:
            return Constants.browserPageSize
        case .authorWorkshop:
            return Constants.authorWorkshopPageSize
        }
    }

    func loadBrowserCache(
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

    func saveBrowserCache(
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
        let normalized = safeCacheComponent(for: query, fallback: "all")
        let theme = themeFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let age = ageRatingFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let resolution = resolutionFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let category = categoryFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let period = source.supportsTimeRange ? trendingWindow.rawValue : "na"
        return cacheDirectoryURL.appendingPathComponent("\(source.rawValue)-\(period)-\(theme)-\(age)-\(resolution)-\(category)-\(normalized).json")
    }

    private func safeCacheComponent(for value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let ascii = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .map { scalar -> Character in
                let scalarString = String(scalar).lowercased()
                return scalarString.range(of: #"^[a-z0-9]$"#, options: .regularExpression) != nil
                    ? (scalarString.first ?? "-")
                    : "-"
            }
        let slug = String(ascii)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let digest = Self.stableCacheDigest(for: trimmed)
        if slug.isEmpty {
            return "\(fallback)-\(digest)"
        }
        return "\(String(slug.prefix(48)))-\(digest)"
    }

    private static func stableCacheDigest(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
