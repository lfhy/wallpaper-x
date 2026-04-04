//
//  OnlineLibraryDownloadsView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  已下载项管理视图入口。
//  网格底层使用 AppKit NSCollectionView（AppKitOLDownloadsGridView），
//  视觉效果与 VideoLibrary 1:1 对齐（hover 放大 + 描边动画）。
//

import SwiftUI
import AppKit
import AVFoundation

// MARK: - 主视图

struct OnlineLibraryDownloadsView: View {
    @ObservedObject private var service = OnlineLibraryService.shared

    var body: some View {
        ZStack {
            AppKitOLDownloadsGridView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inspectorHostBridge(
            module: .onlineLibrary,
            selectedItem: service.selectedDownloadedItemIDForInspector,
            makePresentation: { itemID in
                let snapshot = OnlineLibraryDownloadsInspectorSnapshot.load(itemID: itemID)
                return .infoPanel(
                    cardID: "online-download-\(itemID)",
                    title: snapshot?.title ?? "online_\(itemID).mp4",
                    subtitle: "在线图库已下载项",
                    preferredWidth: 356,
                    focusPolicy: .preserveCurrentResponder
                )
            },
            onSelectionCleared: {
                service.dismissSelectedDownloadedInspector()
            },
            content: { itemID in
                OnlineLibraryDownloadsInspectorView(itemID: itemID)
            }
        )
        .inspectorHostAutoClose(module: .onlineLibrary) {
            service.dismissSelectedDownloadedInspector()
        }
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}

