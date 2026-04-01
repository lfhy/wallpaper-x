//
//  SILEntryView.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
import SwiftUI
import AppKit
import Combine

// MARK: - 对外入口

public struct StaticImageLibraryEntryView: View {
    /// nil 表示显示全部图片，非 nil 表示只显示该标签下的图片
    var silTag: String? = nil
    public init(silTag: String? = nil) { self.silTag = silTag }
    @StateObject private var service = SILService.shared
    public var body: some View {
        let wallpapers = silTag.map { tag in
            service.sortedWallpapers.filter { $0.tags.contains(tag) }
        } ?? service.sortedWallpapers
        SILBridgeView(
            wallpapers: wallpapers,
            zoomOffset: service.gridZoomOffset,
            selectedID: service.selectedID,
            selectedIDs: service.selectedIDs,
            isMultiSelectMode: service.isMultiSelectMode,
            silTag: silTag
        )
        .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - NSViewRepresentable 桥接

struct SILBridgeView: NSViewRepresentable {
    let wallpapers: [SILWallpaper]
    let zoomOffset: Int
    let selectedID: String?
    let selectedIDs: Set<String>
    let isMultiSelectMode: Bool
    /// nil 表示「我的图片」全库视图，非 nil 表示标签子视图
    var silTag: String? = nil

    func makeNSView(context: Context) -> SILGridContainerView {
        let container = SILGridContainerView()
        container.currentSILTag = silTag
        container.update(wallpapers: wallpapers)
        return container
    }

    func updateNSView(_ nsView: SILGridContainerView, context: Context) {
        nsView.currentSILTag = silTag
        nsView.update(wallpapers: wallpapers)
        nsView.invalidateLayout()
        nsView.scheduleSelectionVisualUpdate()
        // 多选模式变化时立即刷新所有可见 item（复选框显隐）
        nsView.refreshVisibleItemsIfNeeded(isMultiSelectMode: isMultiSelectMode)
    }
}
