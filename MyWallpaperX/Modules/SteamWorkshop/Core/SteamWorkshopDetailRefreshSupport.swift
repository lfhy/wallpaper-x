//
//  SteamWorkshopDetailRefreshSupport.swift
//  MyWallpaperX
//

import Foundation

enum SteamWorkshopDetailRefreshSupport {
    static func needsRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        item.detailFields.isEmpty
            || item.fileSizeText == nil
            || item.resolutionText == nil
            || item.workshopTypeText == nil
            || item.previewImageURL == nil
            || item.author == "未知作者"
            || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
    }

    static func makeStub(from item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowseStub {
        SteamWorkshopBrowseStub(
            id: item.id,
            title: item.title,
            author: item.author,
            authorProfileURL: item.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            previewImageURL: item.previewImageURL
        )
    }

    static func cachedItemNeedsHydration(for stub: SteamWorkshopBrowseStub) -> Bool {
        guard let cached = SteamWorkshopService.loadDetailCache(id: stub.id) else { return true }
        let merged = SteamWorkshopService.mergeStub(stub, into: cached)
        return needsRefresh(merged)
    }
}
