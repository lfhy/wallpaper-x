//
//  SteamWorkshopService+LibraryRecords.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
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
        let candidates = videoFileCandidates(in: directory)
        guard !candidates.isEmpty else { return nil }

        if let preferredFileName {
            let normalizedPreferredPath = preferredFileName
                .replacingOccurrences(of: "\\", with: "/")
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedPreferredPath.isEmpty {
                if let exactMatch = candidates.first(where: {
                    relativePath(for: $0, under: directory).lowercased() == normalizedPreferredPath
                }) {
                    return exactMatch
                }

                let preferredBaseName = URL(fileURLWithPath: normalizedPreferredPath).lastPathComponent
                if let namedMatch = candidates.first(where: {
                    $0.lastPathComponent.caseInsensitiveCompare(preferredBaseName) == .orderedSame
                }) {
                    return namedMatch
                }
            }
        }

        return candidates.max { lhs, rhs in
            let lhsSize = ((try? lhs.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            let rhsSize = ((try? rhs.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            if lhsSize != rhsSize {
                return lhsSize < rhsSize
            }

            let lhsRelativePath = relativePath(for: lhs, under: directory)
            let rhsRelativePath = relativePath(for: rhs, under: directory)
            let lhsDepth = lhsRelativePath.split(separator: "/").count
            let rhsDepth = rhsRelativePath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth > rhsDepth
            }
            return lhsRelativePath.localizedStandardCompare(rhsRelativePath) == .orderedDescending
        }
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

    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? {
        if let selectedBrowserItem, selectedBrowserItem.id == id {
            return selectedBrowserItem
        }
        if let browserItem = browserItems.first(where: { $0.id == id }) {
            return browserItem
        }
        return Self.loadDetailCache(id: id)
    }

    static func cachedItemNeedsHydration(for stub: SteamWorkshopBrowseStub) -> Bool {
        SteamWorkshopDetailRefreshSupport.cachedItemNeedsHydration(for: stub)
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

    private func videoFileCandidates(in directory: URL) -> [URL] {
        let supportedExtensions = Set(["mp4", "webm", "mov", "m4v"])
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for case let candidate as URL in enumerator {
            guard supportedExtensions.contains(candidate.pathExtension.localizedLowercase) else { continue }
            let isRegularFile = (try? candidate.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? true
            guard isRegularFile else { continue }
            candidates.append(candidate)
        }

        return candidates.sorted {
            relativePath(for: $0, under: directory).localizedStandardCompare(relativePath(for: $1, under: directory)) == .orderedAscending
        }
    }

    private func relativePath(for fileURL: URL, under directory: URL) -> String {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(directoryPath) else {
            return fileURL.lastPathComponent
        }
        let suffix = filePath.dropFirst(directoryPath.count)
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func fileSizeText(for url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
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
}
