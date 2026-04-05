import Foundation

extension SteamWorkshopService {
    static func shouldEagerlyResolvePreviewKind(for requestPriority: SteamWorkshopDetailRequestPriority) -> Bool {
        requestPriority == .userInitiated
    }

    static func maybeEnrichPreviewKind(
        for item: SteamWorkshopBrowserItem,
        requestPriority: SteamWorkshopDetailRequestPriority
    ) async throws -> SteamWorkshopBrowserItem {
        guard shouldEagerlyResolvePreviewKind(for: requestPriority) else {
            return item
        }
        return try await enrichPreviewKind(for: item, requestPriority: requestPriority)
    }

    static func fetchWorkshopStubPage(
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

    static func fetchWorkshopItems(
        stubs: [SteamWorkshopBrowseStub],
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> [SteamWorkshopBrowserItem] {
        guard !stubs.isEmpty else { return [] }
        var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
        var unresolvedStubs: [SteamWorkshopBrowseStub] = []
        itemsByID.reserveCapacity(stubs.count)
        unresolvedStubs.reserveCapacity(stubs.count)

        for stub in stubs {
            if let cached = loadDetailCache(id: stub.id) {
                let merged = mergeStub(stub, into: cached)
                let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
                if enriched != cached {
                    saveDetailCache(item: enriched)
                }
                itemsByID[stub.id] = enriched
            } else {
                unresolvedStubs.append(stub)
            }
        }

        let detailsByID = try await fetchPublishedFileDetails(
            ids: unresolvedStubs.map(\.id),
            requestPriority: requestPriority
        )
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
                    allowHTMLFallback: false,
                    requestPriority: requestPriority
                )
                itemsByID[stub.id] = item
                continue
            }

            do {
                let item = try await fetchWorkshopItem(
                    stub: stub,
                    officialDetail: nil,
                    allowHTMLFallback: true,
                    requestPriority: requestPriority
                )
                itemsByID[stub.id] = item
            } catch {
                let fallback = fallbackBrowserItem(from: stub)
                let enrichedFallback = try await maybeEnrichPreviewKind(for: fallback, requestPriority: requestPriority)
                itemsByID[stub.id] = enrichedFallback
            }
        }

        return stubs.compactMap { itemsByID[$0.id] }
    }

    static func prewarmDetailCache(for stubs: [SteamWorkshopBrowseStub]) async throws {
        let uncachedStubs = stubs.filter { loadDetailCache(id: $0.id) == nil }
        guard !uncachedStubs.isEmpty else { return }

        var startIndex = 0
        while startIndex < uncachedStubs.count {
            let endIndex = min(startIndex + Constants.detailPrefetchBatchSize, uncachedStubs.count)
            let batch = Array(uncachedStubs[startIndex..<endIndex])
            let detailsByID = try await fetchPublishedFileDetails(
                ids: batch.map(\.id),
                requestPriority: .background
            )
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

    static func fetchWorkshopItem(
        stub: SteamWorkshopBrowseStub,
        officialDetail: SteamWorkshopPublishedFileDetail? = nil,
        allowHTMLFallback: Bool = true,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        if let cached = loadDetailCache(id: stub.id) {
            let merged = await applyingCachedAuthorNameIfPossible(to: mergeStub(stub, into: cached))
            let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
            if enriched != cached {
                saveDetailCache(item: enriched)
            }
            return enriched
        }

        let detail = if let officialDetail {
            officialDetail
        } else {
            try await fetchPublishedFileDetails(
                ids: [stub.id],
                requestPriority: requestPriority
            )[stub.id]
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
                let htmlItem = try await fetchWorkshopItemFromHTML(
                    stub: stub,
                    requestPriority: requestPriority
                )
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
        let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
        saveDetailCache(item: enriched)
        return enriched
    }

    static func fetchWorkshopItemFromHTML(
        stub: SteamWorkshopBrowseStub,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        let detailURL = makeDetailURL(id: stub.id)
        let html = try await fetchHTML(url: detailURL, requestPriority: requestPriority)
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

    static func fetchPublishedFileDetails(
        ids: [String],
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> [String: SteamWorkshopPublishedFileDetail] {
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
        let frozenRequest = request

        let (data, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
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

    static func item(from detail: SteamWorkshopPublishedFileDetail, stub: SteamWorkshopBrowseStub) async -> SteamWorkshopBrowserItem {
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

    static func detailRepresentsVideo(_ detail: SteamWorkshopPublishedFileDetail) -> Bool {
        detail.tags.contains { $0.tag.localizedCaseInsensitiveContains("Video") }
    }

    static func shouldSupplementWithHTML(item: SteamWorkshopBrowserItem) -> Bool {
        item.author == "未知作者"
            || item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || item.previewImageURL == nil
            || item.authorWorkshopURL == nil
    }

    static func mergeDetailedItem(
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

    static func fetchHTML(
        url: URL,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let frozenRequest = request
        let (data, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
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

    static func enrichPreviewKind(
        for item: SteamWorkshopBrowserItem,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        if item.previewAssetKind != .unknown {
            return item
        }
        guard let previewImageURL = item.previewImageURL else {
            return item
        }

        let mimeType = try? await fetchPreviewMimeType(url: previewImageURL, requestPriority: requestPriority)
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

    static func fetchPreviewMimeType(
        url: URL,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        let frozenRequest = request
        let (_, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return http.value(forHTTPHeaderField: "Content-Type")
    }

    static func withPreviewKind(_ previewKind: SteamWorkshopPreviewAssetKind, item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
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

    static func fallbackBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
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

    static func seededBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        guard let cached = loadDetailCache(id: stub.id) else {
            return fallbackBrowserItem(from: stub)
        }
        return mergeStub(stub, into: cached)
    }

    static func mergeStub(_ stub: SteamWorkshopBrowseStub, into item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
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
}
