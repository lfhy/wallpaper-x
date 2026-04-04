//
//  VideoLibraryInspectorView.swift
//  MyWallpaperX
//

import SwiftUI

struct VideoLibraryInspectorView: View {
    let wallpaper: VideoWallpaper

    @State private var details: WallpaperInspectorDetails?
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorHeader
                metadataSection
                tagsSection
                pathSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .task(id: wallpaper.id) {
            loadDetails()
        }
        .onDisappear {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wallpaper.displayTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            Text(headerSummary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if let details {
            inspectorSection("媒体信息") {
                inspectorRow("文件名", details.fileName)
                inspectorRow("大小", details.fileSizeText)
                inspectorRow("格式", details.formatText)
                inspectorRow("持续时间", details.durationText)
                inspectorRow("编解码器", details.codecText)
                inspectorRow("分辨率", details.resolutionText)
                inspectorRow("添加时间", details.addedDateText)
            }
        } else {
            ProgressView("正在读取文件信息…")
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !wallpaper.tags.isEmpty {
            inspectorSection("标签") {
                Text(wallpaper.tags.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var pathSection: some View {
        if let details {
            inspectorSection("文件位置") {
                Text(details.pathText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headerSummary: String {
        var parts: [String] = []
        if let fileSize = wallpaper.fileSize {
            parts.append(String(format: "%.2f MB", Double(fileSize) / (1024 * 1024)))
        }
        if let duration = wallpaper.duration {
            parts.append(formatDuration(duration))
        }
        if let resolution = wallpaper.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        return parts.isEmpty ? "详情信息" : parts.joined(separator: " · ")
    }

    private func loadDetails() {
        loadingTask?.cancel()
        details = nil
        loadingTask = loadWallpaperInspectorDetails(for: wallpaper) { loadedDetails in
            details = loadedDetails
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func formatDuration(_ duration: Int) -> String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
