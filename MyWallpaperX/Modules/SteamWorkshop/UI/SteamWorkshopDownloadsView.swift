//
//  SteamWorkshopDownloadsView.swift
//  MyWallpaperX
//

import SwiftUI

struct SteamWorkshopDownloadsView: View {
    var body: some View {
        SteamWorkshopDownloadsContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SteamWorkshopDownloadsContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        AppKitSteamWorkshopDownloadsGridView(
            service: service,
            onSetAsWallpaper: { record in
                service.setAsWallpaper(record)
            },
            onReveal: { record in
                service.revealItem(record)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.reloadInstalledItems()
        }
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
}
