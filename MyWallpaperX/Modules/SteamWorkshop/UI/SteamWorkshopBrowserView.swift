//
//  SteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import SwiftUI

public struct SteamWorkshopEntryView: View {
    public init() {}

    public var body: some View {
        SteamWorkshopFocusHost(module: .steamWorkshop, content: SteamWorkshopBrowserContentView())
            .ignoresSafeArea(.container, edges: .top)
    }
}

private struct SteamWorkshopBrowserContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SteamWorkshopWebView(
                url: service.requestedURL,
                navigationVersion: service.navigationVersion,
                onNavigationChanged: { url, title in
                    service.updateCurrentPage(url: url, title: title)
                }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("下载失败", isPresented: Binding(
            get: { service.downloadError != nil },
            set: { if !$0 { service.downloadError = nil } }
        )) {
            Button("确定", role: .cancel) {
                service.downloadError = nil
            }
        } message: {
            Text(service.downloadError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.currentPageTitle)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    Text("浏览使用真实 Steam 创意工坊页面；下载通过本机 `steamcmd` 匿名执行，并直接落盘到 Wallpaper Engine workshop 目录。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(service.activeDownloadItemID == nil ? "下载当前项目" : "下载中…") {
                    service.downloadCurrentItem()
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.currentWorkshopItemID == nil || service.activeDownloadItemID != nil)
            }

            HStack(spacing: 14) {
                Label(service.currentWorkshopItemID ?? "未定位到具体项目", systemImage: "number")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Label(service.statusMessage, systemImage: "shippingbox")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
