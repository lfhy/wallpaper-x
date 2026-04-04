//
//  VideoLibraryInspectorView.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit

struct VideoLibraryInspectorView: View {
    let wallpaper: VideoWallpaper

    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @State private var details: WallpaperInspectorDetails?
    @State private var loadingTask: Task<Void, Never>?
    private let previewHeight: CGFloat = 156
    private let topScrollFadeHeight: CGFloat = 12
    private let bottomScrollFadeHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    contentSection
                    tagsSection
                    fileLocationSection
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                VideoLibraryScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }
            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: wallpaper.id) {
            loadDetails()
        }
        .onDisappear {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    private var currentWallpaper: VideoWallpaper {
        wallpaperManager.wallpapers.first(where: { $0.id == wallpaper.id }) ?? wallpaper
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: currentWallpaper.path)
    }

    private var previewImage: NSImage? {
        if let thumbPath = wallpaperManager.resolvedThumbnailPath(for: currentWallpaper),
           let image = NSImage(contentsOfFile: thumbPath) {
            return image
        }
        if let staticFramePath = currentWallpaper.staticFramePath,
           FileManager.default.fileExists(atPath: staticFramePath),
           let image = NSImage(contentsOfFile: staticFramePath) {
            return image
        }
        return nil
    }

    private var noticeItems: [(icon: String, text: String)] {
        var items: [(icon: String, text: String)] = []
        if !fileExists {
            items.append((
                icon: "exclamationmark.triangle.fill",
                text: "源文件不存在，详情信息可能不是最新状态"
            ))
        }
        if previewImage == nil {
            items.append((
                icon: "photo.on.rectangle.angled",
                text: "当前未找到缩略图，正在使用占位预览"
            ))
        }
        return items
    }

    private var secondaryFactText: String? {
        guard let details else { return nil }
        return [details.fileSizeText, details.formatText, details.durationText]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        guard let details else { return [] }
        return [
            ("编解码器", details.codecText),
            ("分辨率", details.resolutionText),
            ("添加时间", details.addedDateText)
        ]
        .filter { !$0.1.isEmpty }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: .windowBackgroundColor),
                                Color(nsColor: .controlBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "film")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(currentWallpaper.displayTitle)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryFactText {
                Text(secondaryFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if details != nil {
            VStack(alignment: .leading, spacing: 14) {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                VStack(alignment: .leading, spacing: 6) {
                    Text("原数据")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(Array(metadataFacts.enumerated()), id: \.offset) { _, fact in
                            inspectorFact(label: fact.0, value: fact.1)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        } else {
            ProgressView("正在读取文件信息…")
                .controlSize(.small)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 6) {
                Text("标签")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if currentWallpaper.tags.isEmpty {
                    Text("当前未加入任何标签")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(currentWallpaper.tags, id: \.self) { tag in
                                tagBadge(tag)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var fileLocationSection: some View {
        if let details {
            VStack(alignment: .leading, spacing: 14) {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                VStack(alignment: .leading, spacing: 6) {
                    Text("文件位置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(details.pathText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var noticeSection: some View {
        if !noticeItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                ForEach(Array(noticeItems.enumerated()), id: \.offset) { _, item in
                    VideoLibraryInlineNotice(
                        icon: item.icon,
                        text: item.text
                    )
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button {
                wallpaperManager.markCardInteraction()
                wallpaperManager.requestSetAsWallpaper(currentWallpaper)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("设为壁纸")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(VideoLibraryFooterButtonStyle(kind: .primary))

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: currentWallpaper.path)])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("查看文件")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(VideoLibraryFooterButtonStyle(kind: .secondary))

            Button {
                UIActionHelper.toggleFavoriteSelection(
                    manager: wallpaperManager,
                    selection: wallpaperManager.currentSelectionContext
                )
            } label: {
                Image(systemName: currentWallpaper.isFavorite ? "heart.fill" : "heart")
                    .frame(width: 18, height: 18)
                    .frame(width: 46, height: 38)
            }
            .buttonStyle(VideoLibraryFooterButtonStyle(kind: .secondary))
            .help(currentWallpaper.isFavorite ? "取消收藏" : "收藏")
            .accessibilityLabel(currentWallpaper.isFavorite ? "取消收藏" : "收藏")

            Button {
                UIActionHelper.presentTagPicker(
                    manager: wallpaperManager,
                    window: nil
                ) {
                }
            } label: {
                Image(systemName: "tag")
                    .frame(width: 18, height: 18)
                    .frame(width: 46, height: 38)
            }
            .buttonStyle(VideoLibraryFooterButtonStyle(kind: .secondary))
            .help("添加标签")
            .accessibilityLabel("添加标签")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func loadDetails() {
        loadingTask?.cancel()
        details = nil
        loadingTask = loadWallpaperInspectorDetails(for: currentWallpaper) { loadedDetails in
            details = loadedDetails
        }
    }

    private func inspectorFact(
        label: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.12))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
            }
    }
}

private struct VideoLibraryInlineNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct VideoLibraryScrollFadeMask: View {
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, topFadeHeight + bottomFadeHeight + 1)
            let topFadeRatio = min(max(topFadeHeight / height, 0.01), 0.18)
            let bottomFadeRatio = min(max(bottomFadeHeight / height, 0.01), 0.24)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: topFadeRatio),
                    .init(color: .black, location: 1 - bottomFadeRatio),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum VideoLibraryFooterButtonKind {
    case primary
    case secondary
}

private struct VideoLibraryFooterButtonStyle: ButtonStyle {
    var kind: VideoLibraryFooterButtonKind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .background(backgroundFill(isPressed: configuration.isPressed))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor.opacity(isEnabled ? 1 : 0.55), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return Color(nsColor: .labelColor)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .systemBlue).opacity(0.42)
        case .secondary:
            return Color.white.opacity(0.16)
        }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        let opacity = isPressed ? 0.9 : 1.0

        switch kind {
        case .primary:
            Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue)
        case .secondary:
            Color.black.opacity(0.14 * opacity)
        }
    }
}
