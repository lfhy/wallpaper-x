//
//  SILInspectorView.swift
//  MyWallpaperX
//

import SwiftUI

struct SILInspectorView: View {
    let wallpaper: SILWallpaper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                metadataSection
                tagsSection
                pathSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wallpaper.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            Text(headerSummary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        inspectorSection("图片信息") {
            inspectorRow("文件名", fileName)
            if let fileSizeText {
                inspectorRow("大小", fileSizeText)
            }
            if let resolutionText {
                inspectorRow("尺寸", resolutionText)
            }
            inspectorRow("添加时间", dateFormatter.string(from: wallpaper.addedAt))
            if wallpaper.lastUsed > .distantPast {
                inspectorRow("最近使用", dateFormatter.string(from: wallpaper.lastUsed))
            }
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

    private var pathSection: some View {
        inspectorSection("文件位置") {
            Text(wallpaper.path)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fileName: String {
        URL(fileURLWithPath: wallpaper.path).lastPathComponent
    }

    private var fileSizeText: String? {
        guard let fileSize = wallpaper.fileSize else { return nil }
        return String(format: "%.2f MB", Double(fileSize) / 1_048_576)
    }

    private var resolutionText: String? {
        guard let width = wallpaper.pixelWidth,
              let height = wallpaper.pixelHeight else { return nil }
        return "\(width) × \(height)"
    }

    private var headerSummary: String {
        var parts: [String] = []
        if let fileSizeText {
            parts.append(fileSizeText)
        }
        if let resolutionText {
            parts.append(resolutionText)
        }
        return parts.isEmpty ? "详情信息" : parts.joined(separator: " · ")
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
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
}
