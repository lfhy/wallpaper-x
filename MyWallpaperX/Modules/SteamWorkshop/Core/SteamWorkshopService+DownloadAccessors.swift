//
//  SteamWorkshopService+DownloadAccessors.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    var filteredDownloads: [SteamWorkshopDownloadRecord] {
        displayedDownloads
    }

    func firstDisplayedDownloadID(in ids: Set<String>) -> String? {
        displayedDownloads.first { ids.contains($0.id) }?.id
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
        isDownloadsMultiSelectMode && !displayedDownloads.isEmpty
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
}
