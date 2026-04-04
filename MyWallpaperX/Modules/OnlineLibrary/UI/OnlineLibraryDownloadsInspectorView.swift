//
//  OnlineLibraryDownloadsInspectorView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//

import SwiftUI
import AVFoundation

struct OnlineLibraryDownloadsInspectorView: View {
    let itemID: Int

    private var snapshot: OnlineLibraryDownloadsInspectorSnapshot? {
        OnlineLibraryDownloadsInspectorSnapshot.load(itemID: itemID)
    }

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        inspectorSection("文件") {
                            inspectorRow("名称", snapshot.title)
                            inspectorRow("格式", snapshot.fileExtension)
                            inspectorRow("大小", snapshot.fileSizeText)
                            inspectorRow("时长", snapshot.durationText)
                            inspectorRow("分辨率", snapshot.resolutionText)
                            inspectorRow("添加时间", snapshot.creationDateText)
                        }

                        inspectorSection("来源") {
                            inspectorRow("Pixabay ID", "\(snapshot.id)")
                            inspectorRow("存储位置", snapshot.path)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("无法读取该下载项信息")
                        .font(.system(size: 14, weight: .semibold))
                    Text("文件可能已被移动或删除。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
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

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
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
    let path: String

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
            path: url.path
        )
    }
}
