//
//  SILInspectorView.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit

struct SILInspectorView: View {
    let wallpaper: SILWallpaper

    @State private var refreshToken = 0
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
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                SILScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }

            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewImage: NSImage? {
        SILThumbnailStore.sharedCache.cachedOrDiskImage(forKey: wallpaper.path)
    }

    private var secondaryFactText: String? {
        [fileSizeText, formatText]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        [
            resolutionText.map { ("分辨率", $0) },
            ("添加时间", dateFormatter.string(from: wallpaper.addedAt)),
            wallpaper.lastUsed > .distantPast ? ("最近使用", dateFormatter.string(from: wallpaper.lastUsed)) : nil
        ]
        .compactMap { $0 }
    }

    private var notices: [(icon: String, text: String)] {
        var result: [(String, String)] = []

        if !FileManager.default.fileExists(atPath: wallpaper.path) {
            result.append(("exclamationmark.triangle.fill", "原始图片文件当前不可用"))
        }

        if SILService.shared.currentActiveWallpaperPath == wallpaper.path {
            result.append(("photo.fill", "当前桌面正在使用这张图片"))
        }

        return result
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SILInspectorPreviewSurface(image: previewImage)
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(wallpaper.title)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !metadataFacts.isEmpty {
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

            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 6) {
                Text("文件位置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(wallpaper.path)
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

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 6) {
                Text("标签")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if wallpaper.tags.isEmpty {
                    Text("当前未加入任何标签")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(wallpaper.tags, id: \.self) { tag in
                                Text(tag)
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
                }
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var noticeSection: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    HStack(spacing: 8) {
                        Image(systemName: notice.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(notice.text)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
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
            .buttonStyle(SILInspectorFooterButtonStyle(kind: .secondary))

            Button {
                presentTagPicker()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 14, weight: .semibold))
                    Text("添加标签")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(SILInspectorFooterButtonStyle(kind: .secondary))
            .disabled(SILService.shared.silTags.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .id(refreshToken)
    }

    private var fileSizeText: String? {
        guard let fileSize = wallpaper.fileSize else { return nil }
        return String(format: "%.2f MB", Double(fileSize) / 1_048_576)
    }

    private var formatText: String? {
        let ext = URL(fileURLWithPath: wallpaper.path).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }

    private var resolutionText: String? {
        guard let width = wallpaper.pixelWidth,
              let height = wallpaper.pixelHeight else { return nil }
        return "\(width) × \(height)"
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func presentTagPicker() {
        let service = SILService.shared
        guard !service.silTags.isEmpty else { return }

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        picker.addItems(withTitles: service.silTags)
        picker.selectItem(at: 0)

        let alert = makeAppAlert(
            title: "添加图片标签",
            message: "请选择要添加的标签",
            buttons: ["确定", "取消"],
            accessoryView: picker
        )

        presentAppAlert(alert, in: appModalHostWindow()) { response in
            guard response == .alertFirstButtonReturn,
                  let tag = picker.titleOfSelectedItem,
                  !tag.isEmpty else { return }
            SILService.shared.addSILTag(tag, toSelected: [wallpaper.id])
            refreshToken += 1
        }
    }

    private func inspectorFact(label: String, value: String) -> some View {
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
}

private struct SILInspectorPreviewSurface: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color(red: 0.84, green: 0.91, blue: 1.0).opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: "photo")
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
    }
}

private enum SILInspectorFooterButtonKind {
    case secondary
}

private struct SILInspectorFooterButtonStyle: ButtonStyle {
    let kind: SILInspectorFooterButtonKind
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
        case .secondary:
            return Color(nsColor: .labelColor)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary:
            return Color.white.opacity(0.16)
        }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        let opacity = isPressed ? 0.9 : 1.0

        switch kind {
        case .secondary:
            Color.black.opacity(0.14 * opacity)
        }
    }
}

private struct SILScrollFadeMask: View {
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
