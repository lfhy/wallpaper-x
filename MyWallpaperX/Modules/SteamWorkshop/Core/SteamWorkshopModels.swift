import Foundation

enum SteamWorkshopPreviewAssetKind: String, Equatable, Codable {
    case unknown
    case stillImage
    case animatedImage
    case video

    var isAnimated: Bool {
        self == .animatedImage || self == .video
    }
}

struct SteamWorkshopDetailField: Identifiable, Equatable, Codable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}

struct SteamWorkshopBrowserItem: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let author: String
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let hasAdultContent: Bool
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let previewAssetKind: SteamWorkshopPreviewAssetKind
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let lifetimeFavoritesText: String?
    let lifetimeSubscriptionsText: String?
    let visibilityText: String?
    let moderationText: String?
    let detailFields: [SteamWorkshopDetailField]
    let detailURL: URL

    var primaryMetaText: String {
        [fileSizeText, resolutionText]
            .compactMap { $0 }
            .joined(separator: "  ")
    }

    var secondaryMetaText: String {
        [workshopTypeText, ageRatingText, genreText, updatedText]
            .compactMap { $0 }
            .joined(separator: "  ")
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

    var failureMessage: String? {
        guard case let .failed(message) = status else { return nil }
        return message
    }

    var isPlayable: Bool {
        status == .ready && videoURL != nil
    }
}
