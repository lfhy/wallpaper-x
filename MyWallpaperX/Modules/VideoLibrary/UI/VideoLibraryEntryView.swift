//
//  VideoLibraryEntryView.swift
//  MyWallpaperX
//
//  视频壁纸模块对外唯一入口。
//  Shell 层的 DetailView 只引用此文件中的类型，不直接引用模块内部实现。
//

import SwiftUI

/// 视频壁纸库入口视图，供 Shell 层的 DetailView 路由使用。
/// 参数全部由 Shell 层从 WallpaperManager 派生后传入，保持模块边界清晰。
struct VideoLibraryEntryView: View {
    let wallpapers: [VideoWallpaper]
    let animatesReorder: Bool
    let animatesInsertDelete: Bool

    var body: some View {
        AppKitLibraryGridView(
            wallpapers: wallpapers,
            animatesReorder: animatesReorder,
            animatesInsertDelete: animatesInsertDelete
        )
    }
}
