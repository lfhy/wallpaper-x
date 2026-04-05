import AppKit

extension SteamWorkshopService {
    func revealDownloadsDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryRootURL])
    }

    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) {
        NSWorkspace.shared.open(item.detailURL)
    }

    func openAuthorProfilePage(for item: SteamWorkshopBrowserItem) {
        if let authorProfileURL = item.authorProfileURL {
            NSWorkspace.shared.open(authorProfileURL)
            return
        }
        if let authorWorkshopURL = item.authorWorkshopURL {
            NSWorkspace.shared.open(authorWorkshopURL)
        }
    }

    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) {
        showAuthorWorkshop(for: item)
    }

    func revealItem(_ record: SteamWorkshopDownloadRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.videoURL ?? record.folderURL])
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
}
