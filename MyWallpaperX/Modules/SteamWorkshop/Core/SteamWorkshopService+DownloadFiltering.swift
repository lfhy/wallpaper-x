//
//  SteamWorkshopService+DownloadFiltering.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    func filteredAndSortedDownloads(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        let query = downloadsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [SteamWorkshopDownloadRecord]
        if query.isEmpty {
            filtered = records
        } else {
            let normalized = query.localizedLowercase
            filtered = records.filter {
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

    func sanitizeDownloadSelectionAgainstDisplayedDownloads() {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let visibleSelection = selectedDownloadIDs.intersection(visibleIDs)
        let normalizedPrimaryID: String? = {
            if let selectedDownloadID, visibleIDs.contains(selectedDownloadID) {
                return selectedDownloadID
            }
            if isDownloadsMultiSelectMode {
                return firstDisplayedDownloadID(in: visibleSelection)
            }
            return nil
        }()
        let normalizedSelectedIDs = isDownloadsMultiSelectMode
            ? visibleSelection
            : (normalizedPrimaryID.map { [$0] } ?? [])
        guard normalizedPrimaryID != selectedDownloadID || normalizedSelectedIDs != selectedDownloadIDs else {
            return
        }
        selectedDownloadID = normalizedPrimaryID
        selectedDownloadIDs = normalizedSelectedIDs
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func clearFilters() {
        themeFilter = .all
        ageRatingFilter = .all
        resolutionFilter = .all
        categoryFilter = .all
    }
}
