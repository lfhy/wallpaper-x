//
//  SteamWorkshopService.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import Combine

enum SteamWorkshopSource: String, CaseIterable, Identifiable {
    case featured
    case recent
    case subscribed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .featured: return "精选"
        case .recent: return "最新"
        case .subscribed: return "订阅"
        }
    }

    var browseFilter: String {
        switch self {
        case .featured: return "trend"
        case .recent: return "mostrecent"
        case .subscribed: return "mysubscriptions"
        }
    }
}

struct SteamWorkshopDownloadRecord: Identifiable, Equatable {
    enum Status: Equatable {
        case downloading
        case ready
        case failed(String)
    }

    let id: String
    let title: String
    let description: String
    let tags: [String]
    let folderURL: URL
    let previewURL: URL?
    let videoURL: URL?
    let updatedAt: Date
    let sizeText: String
    let status: Status

    var statusText: String {
        switch status {
        case .downloading:
            return "下载中"
        case .ready:
            return "已下载"
        case .failed:
            return "下载失败"
        }
    }
}

private struct SteamWorkshopProject: Decodable {
    let title: String?
    let description: String?
    let preview: String?
    let file: String?
    let tags: [String]?
    let workshopid: String?
    let type: String?
}

@MainActor
final class SteamWorkshopService: ObservableObject {
    static let shared = SteamWorkshopService()

    private enum Constants {
        static let workshopAppID = "431960"
        static let steamCommunityBase = "https://steamcommunity.com/workshop/browse/"
        static let steamCmdPath = "/Users/songziqiang/Steam/steamcmd.sh"
        static let installRoot = "/Users/songziqiang/Steam/wallpaper_engine"
    }

    @Published private(set) var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var source: SteamWorkshopSource = .featured {
        didSet { navigateToBrowse() }
    }
    @Published var browserQuery: String = "" {
        didSet { navigateToBrowse() }
    }
    @Published var downloadsQuery: String = ""
    @Published var zoomOffset: Int = 0
    @Published var statusMessage: String = "使用内嵌 Workshop 浏览，下载通过本机 steamcmd 匿名执行。"
    @Published var currentWorkshopItemID: String?
    @Published var currentPageTitle: String = "Steam 创意工坊"
    @Published var requestedURL: URL
    @Published var navigationVersion: Int = 0
    @Published var activeDownloadItemID: String?
    @Published var downloadError: String?

    private init() {
        requestedURL = SteamWorkshopService.makeBrowseURL(source: .featured, query: "")
        reloadInstalledItems()
    }

    var steamCmdURL: URL { URL(fileURLWithPath: Constants.steamCmdPath) }
    var installRootURL: URL { URL(fileURLWithPath: Constants.installRoot, isDirectory: true) }
    var workshopContentRootURL: URL {
        installRootURL
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("workshop", isDirectory: true)
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
    }

    var filteredDownloads: [SteamWorkshopDownloadRecord] {
        let query = downloadsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return downloads }
        let normalized = query.localizedLowercase
        return downloads.filter {
            $0.title.localizedLowercase.contains(normalized)
            || $0.description.localizedLowercase.contains(normalized)
            || $0.tags.contains(where: { $0.localizedLowercase.contains(normalized) })
            || $0.id.localizedLowercase.contains(normalized)
        }
    }

    var downloadsCount: Int { downloads.count }

    func navigateToBrowse() {
        requestedURL = Self.makeBrowseURL(source: source, query: browserQuery)
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
    }

    func refresh() {
        navigationVersion += 1
        if currentWorkshopItemID == nil {
            requestedURL = Self.makeBrowseURL(source: source, query: browserQuery)
        }
        reloadInstalledItems()
    }

    func updateCurrentPage(url: URL?, title: String?) {
        guard let url else { return }
        requestedURL = url
        currentWorkshopItemID = Self.extractWorkshopID(from: url)
        if let title, !title.isEmpty {
            currentPageTitle = title
        } else if let itemID = currentWorkshopItemID {
            currentPageTitle = "Workshop #\(itemID)"
        } else {
            currentPageTitle = "Steam 创意工坊"
        }
    }

    func downloadCurrentItem() {
        guard let itemID = currentWorkshopItemID else {
            downloadError = "当前页面不是具体的创意工坊项目，无法下载。"
            return
        }
        downloadWorkshopItem(id: itemID, pageTitle: currentPageTitle)
    }

    func downloadWorkshopItem(id: String, pageTitle: String? = nil) {
        guard activeDownloadItemID == nil else {
            statusMessage = "已有下载任务在执行，请稍候。"
            return
        }
        activeDownloadItemID = id
        statusMessage = "正在通过 steamcmd 下载 Workshop #\(id)"
        upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .downloading)

        let process = Process()
        process.executableURL = steamCmdURL
        process.arguments = [
            "+force_install_dir", installRootURL.path,
            "+login", "anonymous",
            "+workshop_download_item", Constants.workshopAppID, id, "validate",
            "+quit"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        process.terminationHandler = { [weak self] process in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self, output, id, pageTitle] in
                guard let self else { return }
                self.activeDownloadItemID = nil
                if process.terminationStatus == 0,
                   output.localizedCaseInsensitiveContains("Success. Downloaded item") {
                    self.statusMessage = "已完成 Workshop #\(id) 下载"
                    self.reloadInstalledItems()
                } else {
                    let message = output.isEmpty ? "steamcmd 下载失败，请检查网络与项目可见性。" : output
                    self.downloadError = message
                    self.statusMessage = "Workshop #\(id) 下载失败"
                    self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
                }
            }
        }

        do {
            try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
            try process.run()
        } catch {
            activeDownloadItemID = nil
            let message = "无法启动 steamcmd：\(error.localizedDescription)"
            downloadError = message
            statusMessage = message
            upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
        }
    }

    func reloadInstalledItems() {
        let fileManager = FileManager.default
        let root = workshopContentRootURL
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloads = downloads.filter {
                if case .downloading = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }
            return
        }

        var records: [SteamWorkshopDownloadRecord] = []
        for directory in directories where directory.hasDirectoryPath {
            guard let record = buildInstalledRecord(at: directory) else { continue }
            records.append(record)
        }

        let transient = downloads.filter { record in
            switch record.status {
            case .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
    }

    func revealDownloadsDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([workshopContentRootURL])
    }

    func revealItem(_ record: SteamWorkshopDownloadRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.folderURL])
    }

    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) {
        guard let videoURL = record.videoURL else {
            downloadError = "没有找到可播放的视频文件。"
            return
        }
        NotificationCenter.default.post(
            name: .steamWorkshopVideoReadyToPlay,
            object: nil,
            userInfo: ["localURL": videoURL]
        )
        statusMessage = "已将 \(record.title) 发送到视频库并准备播放"
    }

    private func buildInstalledRecord(at directory: URL) -> SteamWorkshopDownloadRecord? {
        let projectURL = directory.appendingPathComponent("project.json")
        let project = try? JSONDecoder().decode(SteamWorkshopProject.self, from: Data(contentsOf: projectURL))
        let previewURL = project?.preview.flatMap { preview in
            let url = directory.appendingPathComponent(preview)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let videoURL = resolveVideoURL(in: directory, preferredFileName: project?.file)
        let attributes = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        let updatedAt = attributes?.contentModificationDate ?? Date()
        let title = project?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = project?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = project?.tags ?? []
        let sizeText = videoURL.flatMap { fileSizeText(for: $0) } ?? "未知大小"
        let identifier = project?.workshopid ?? directory.lastPathComponent

        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : "Workshop #\(identifier)",
            description: description,
            tags: tags,
            folderURL: directory,
            previewURL: previewURL,
            videoURL: videoURL,
            updatedAt: updatedAt,
            sizeText: sizeText,
            status: .ready
        )
    }

    private func resolveVideoURL(in directory: URL, preferredFileName: String?) -> URL? {
        if let preferredFileName {
            let preferredURL = directory.appendingPathComponent(preferredFileName)
            if FileManager.default.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let supportedExtensions = Set(["mp4", "webm", "mov", "m4v"])
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return files.first {
            supportedExtensions.contains($0.pathExtension.localizedLowercase)
        }
    }

    private func fileSizeText(for url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        let mb = Double(size) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1fGB", mb / 1024)
        }
        if mb >= 100 {
            return String(format: "%.0fMB", mb)
        }
        return String(format: "%.1fMB", mb)
    }

    private func upsertTransientRecord(id: String, title: String, status: SteamWorkshopDownloadRecord.Status) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let previous = downloads[index]
            downloads[index] = SteamWorkshopDownloadRecord(
                id: id,
                title: previous.title,
                description: previous.description,
                tags: previous.tags,
                folderURL: previous.folderURL,
                previewURL: previous.previewURL,
                videoURL: previous.videoURL,
                updatedAt: Date(),
                sizeText: previous.sizeText,
                status: status
            )
            return
        }

        let folderURL = workshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        downloads.insert(
            SteamWorkshopDownloadRecord(
                id: id,
                title: title,
                description: "",
                tags: [],
                folderURL: folderURL,
                previewURL: nil,
                videoURL: nil,
                updatedAt: Date(),
                sizeText: "等待下载",
                status: status
            ),
            at: 0
        )
    }

    private static func makeBrowseURL(source: SteamWorkshopSource, query: String) -> URL {
        var components = URLComponents(string: Constants.steamCommunityBase)!
        components.queryItems = [
            URLQueryItem(name: "appid", value: Constants.workshopAppID),
            URLQueryItem(name: "searchtext", value: query),
            URLQueryItem(name: "browsesort", value: source.browseFilter),
            URLQueryItem(name: "section", value: "readytouseitems"),
            URLQueryItem(name: "requiredtags[]", value: "Video"),
            URLQueryItem(name: "actualsort", value: source.browseFilter),
            URLQueryItem(name: "p", value: "1")
        ]
        return components.url!
    }

    private static func extractWorkshopID(from url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return id
        }
        let pathComponents = url.pathComponents
        if let index = pathComponents.firstIndex(of: "filedetails"),
           pathComponents.indices.contains(index + 1) {
            let next = pathComponents[index + 1]
            if next.allSatisfy(\.isNumber) {
                return next
            }
        }
        return nil
    }
}
