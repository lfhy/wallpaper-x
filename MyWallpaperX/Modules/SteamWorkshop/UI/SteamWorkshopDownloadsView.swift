//
//  SteamWorkshopDownloadsView.swift
//  MyWallpaperX
//

import SwiftUI

struct SteamWorkshopDownloadsView: View {
    var body: some View {
        SteamWorkshopFocusHost(module: .steamWorkshop, content: SteamWorkshopDownloadsContentView())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SteamWorkshopDownloadsContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        GeometryReader { proxy in
            let width = max(420, proxy.size.width - 48)
            let columnCount = GridLayoutHelper.columnCount(
                for: width,
                zoomOffset: service.zoomOffset,
                minCols: 2,
                maxCols: 4
            )
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if service.filteredDownloads.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(service.filteredDownloads) { record in
                                SteamWorkshopDownloadCard(record: record)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steam 下载页")
                    .font(.system(size: 22, weight: .bold))
                Text("这里展示的是本机 Wallpaper Engine workshop 目录里已经落盘的本地项目。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("刷新本地目录") {
                service.reloadInstalledItems()
            }
            .buttonStyle(.bordered)
            Button("打开下载目录") {
                service.revealDownloadsDirectory()
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("当前 workshop 目录里还没有已下载的视频项目")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct SteamWorkshopDownloadCard: View {
    let record: SteamWorkshopDownloadRecord
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(record.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !record.description.isEmpty {
                    Text(record.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    Text(record.sizeText)
                    Text(record.statusText)
                    if !record.tags.isEmpty {
                        Text(record.tags.joined(separator: " · "))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("设为壁纸") {
                    service.setAsWallpaper(record)
                }
                .buttonStyle(.borderedProminent)
                .disabled(record.videoURL == nil)

                Button("显示文件") {
                    service.revealItem(record)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let previewURL = record.previewURL,
           let image = NSImage(contentsOf: previewURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    statusBadge
                }
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.18, blue: 0.30), Color(red: 0.08, green: 0.25, blue: 0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 148)
                .overlay(alignment: .bottomLeading) {
                    statusBadge
                }
        }
    }

    private var statusBadge: some View {
        Text(record.statusText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.22), in: Capsule())
            .padding(12)
    }
}
