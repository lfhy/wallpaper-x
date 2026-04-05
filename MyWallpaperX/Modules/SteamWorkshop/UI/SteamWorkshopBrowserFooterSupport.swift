//
//  SteamWorkshopBrowserFooterSupport.swift
//  MyWallpaperX
//

import AppKit

enum SteamWorkshopBrowserFooterSupport {
    enum State: Equatable {
        case hidden
        case ready
        case loading
        case exhausted
    }

    static let itemID = "__steam_workshop_grid_footer__"

    static func resolvedState(
        isLoadingMore: Bool,
        hasMore: Bool,
        itemIDs: [String]
    ) -> State {
        if isLoadingMore {
            return .loading
        }
        if hasMore, !itemIDs.isEmpty {
            return .ready
        }
        if !hasMore, !itemIDs.isEmpty {
            return .exhausted
        }
        return .hidden
    }

    static func text(for state: State) -> String {
        switch state {
        case .hidden:
            return ""
        case .ready:
            return "继续下滑以加载更多项目。"
        case .loading:
            return "正在加载更多项目…"
        case .exhausted:
            return "已到达当前可抓取内容底部。受 Steam 官方页面可见性与分页限制影响，部分作品可能无法完整抓取；如需核对，请以 Steam 官方网页为准。"
        }
    }

    static func configure(_ item: AppKitSteamWorkshopBrowserFooterItem, state: State) {
        item.configure(
            text: text(for: state),
            showsProgress: state == .loading
        )
    }

    static func size(
        for state: State,
        boundsWidth: CGFloat,
        sectionInset: NSEdgeInsets
    ) -> NSSize {
        let width = max(120, boundsWidth - sectionInset.left - sectionInset.right)
        let height: CGFloat = state == .exhausted ? 52 : 40
        return NSSize(width: floor(width), height: height)
    }
}
