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
    var body: some View {
        ZStack {
            AppKitOLDownloadsGridView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}


