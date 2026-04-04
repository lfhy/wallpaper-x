//
//  OnlineLibraryDownloadsInspectorView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//

import SwiftUI
import AppKit
import AVFoundation

struct OnlineLibraryDownloadsInspectorView: View {
    let itemID: Int

    private let previewHeight: CGFloat = 156
    private let topScrollFadeHeight: CGFloat = 12
    private let bottomScrollFadeHeight: CGFloat = 20

    private var snapshot: OnlineLibraryDownloadsInspectorSnapshot? {
        OnlineLibraryDownloadsInspectorSnapshot.load(itemID: itemID)
    }

    private var secondaryFactText: String? {
        guard let snapshot else { return nil }
        return [snapshot.fileSizeText, snapshot.durationText, snapshot.fileExtension]
            .filter { !$0.isEmpty && $0 != "未知" }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        guard let snapshot else { return [] }
        return [
            ("分辨率", snapshot.resolutionText),
            ("添加时间", snapshot.creationDateText),
            ("来源平台", snapshot.platformText)
        ]
        .filter { !$0.1.isEmpty && $0.1 != "未知" }
    }

    private var heroBadges: [String] {
        guard let snapshot else { return [] }
        return [
            snapshot.platformText,
            snapshot.fileExtension,
            "已下载"
        ]
    }

    private var statusFactText: String? {
        guard let snapshot else { return nil }
        return [
            snapshot.resolutionText == "未知" ? nil : snapshot.resolutionText,
            snapshot.durationText == "未知" ? nil : snapshot.durationText,
            "Pixabay ID \(snapshot.id)"
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        .nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    metaSection
                    contentSection
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                OnlineLibraryScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }

            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnlineLibraryDownloadsPreviewSurface(
                itemID: itemID,
                previewImage: snapshot?.previewImage
            )
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(snapshot?.title ?? "online_\(itemID).mp4")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryFactText {
                Text(secondaryFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var metaSection: some View {
        if !heroBadges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(heroBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let statusFactText {
                    Text(statusFactText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 14) {
                if !metadataFacts.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.035))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(Array(metadataFacts.enumerated()), id: \.offset) { _, fact in
                            inspectorFact(label: fact.0, value: fact.1)
                        }
                    }
                }

                Divider()
                    .overlay(Color.white.opacity(0.035))

                VStack(alignment: .leading, spacing: 6) {
                    Text("文件位置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(snapshot.path)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 2)
        } else {
            ProgressView("正在读取文件信息…")
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var noticeSection: some View {
        if snapshot == nil {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                OnlineLibraryInlineNotice(
                    icon: "exclamationmark.triangle.fill",
                    text: "当前下载项文件可能已被移动或删除。"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button {
                OnlineLibraryService.shared.setLocalFileAsWallpaper(id: itemID)
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
            .buttonStyle(OnlineLibraryFooterButtonStyle(kind: .primary))
            .disabled(snapshot == nil)

            Button {
                guard let url = snapshot?.fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
            .buttonStyle(OnlineLibraryFooterButtonStyle(kind: .secondary))
            .disabled(snapshot == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func inspectorFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnlineLibraryDownloadsInspectorSnapshot {
    let id: Int
    let title: String
    let fileExtension: String
    let fileSizeText: String
    let durationText: String
    let resolutionText: String
    let creationDateText: String
    let platformText: String
    let path: String
    let fileURL: URL
    let previewImage: NSImage?

    static func load(itemID: Int) -> OnlineLibraryDownloadsInspectorSnapshot? {
        let url = OnlineLibraryService.downloadDirectory.appendingPathComponent("online_\(itemID).mp4")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = attributes[.size] as? Int64 ?? 0
        let creationDate = attributes[.creationDate] as? Date

        let asset = AVURLAsset(url: url)
        let durationSeconds = max(0, Int(asset.duration.seconds.rounded()))

        var resolutionText = "未知"
        if let track = asset.tracks(withMediaType: .video).first {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            let width = Int(abs(transformed.width).rounded())
            let height = Int(abs(transformed.height).rounded())
            if width > 0, height > 0 {
                resolutionText = "\(width)×\(height)"
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        return OnlineLibraryDownloadsInspectorSnapshot(
            id: itemID,
            title: url.lastPathComponent,
            fileExtension: url.pathExtension.uppercased(),
            fileSizeText: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
            durationText: durationSeconds > 0 ? AppKitOLDownloadsItem.formatDuration(durationSeconds) : "未知",
            resolutionText: resolutionText,
            creationDateText: creationDate.map(formatter.string(from:)) ?? "未知",
            platformText: "Pixabay",
            path: url.path,
            fileURL: url,
            previewImage: OLDownloadedThumbnailCache.shared.image(for: itemID)
        )
    }
}

private struct OnlineLibraryDownloadsPreviewSurface: View {
    let itemID: Int
    let previewImage: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color(red: 0.84, green: 0.91, blue: 1.0).opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LinearGradient(
                colors: [.clear, .white.opacity(0.02)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipped()
        .accessibilityLabel("在线图库下载项预览 \(itemID)")
    }
}

private struct OnlineLibraryScrollFadeMask: View {
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, topFadeHeight + bottomFadeHeight + 1)
            let topStop = min(1, topFadeHeight / height)
            let bottomStart = max(0, 1 - (bottomFadeHeight / height))

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: topStop),
                    .init(color: .black, location: bottomStart),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct OnlineLibraryInlineNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum OnlineLibraryFooterButtonKind {
    case primary
    case secondary
}

private struct OnlineLibraryFooterButtonStyle: ButtonStyle {
    var kind: OnlineLibraryFooterButtonKind = .secondary
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
