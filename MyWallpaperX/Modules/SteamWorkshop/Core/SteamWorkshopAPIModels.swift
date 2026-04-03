import Foundation
import CoreGraphics

enum SteamWorkshopBrowseContext: Equatable {
    case discovery
    case authorWorkshop(authorName: String, workshopURL: URL)

    var isAuthorWorkshop: Bool {
        if case .authorWorkshop = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .discovery:
            return "Steam 创意工坊"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 的工坊"
        }
    }

    var cacheKeyComponent: String {
        switch self {
        case .discovery:
            return "discovery"
        case .authorWorkshop(_, let workshopURL):
            let normalized = workshopURL.absoluteString
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let slug = normalized.isEmpty ? "author-workshop" : normalized
            return "author-v2-\(String(slug.prefix(120)))"
        }
    }
}

struct SteamWorkshopProject: Decodable {
    let title: String?
    let description: String?
    let preview: String?
    let file: String?
    let tags: [String]?
    let workshopid: String?
    let type: String?
}

struct SteamWorkshopDetailParseResult {
    let title: String
    let author: String
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let detailFields: [SteamWorkshopDetailField]
}

struct SteamWorkshopPublishedFileResponseEnvelope: Decodable {
    let response: SteamWorkshopPublishedFileResponse
}

struct SteamWorkshopPublishedFileResponse: Decodable {
    let result: Int?
    let resultcount: Int?
    let publishedfiledetails: [SteamWorkshopPublishedFileDetail]
}

struct SteamWorkshopPublishedFileTag: Decodable {
    let tag: String
}

struct SteamWorkshopPublishedFileDetail: Decodable {
    let publishedfileid: String
    let result: Int
    let creator: String?
    let creatorAppID: Int?
    let consumerAppID: Int?
    let fileSize: Int64?
    let previewURL: URL?
    let title: String?
    let description: String?
    let timeCreated: Int64?
    let timeUpdated: Int64?
    let visibility: Int?
    let banned: Int?
    let banReason: String?
    let subscriptions: Int?
    let favorited: Int?
    let lifetimeSubscriptions: Int?
    let lifetimeFavorited: Int?
    let views: Int?
    let tags: [SteamWorkshopPublishedFileTag]

    enum CodingKeys: String, CodingKey {
        case publishedfileid
        case result
        case creator
        case creator_app_id
        case consumer_app_id
        case file_size
        case preview_url
        case title
        case description
        case time_created
        case time_updated
        case visibility
        case banned
        case ban_reason
        case subscriptions
        case favorited
        case lifetime_subscriptions
        case lifetime_favorited
        case views
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publishedfileid = try container.decode(String.self, forKey: .publishedfileid)
        result = Self.decodeLossyInt(from: container, forKey: .result) ?? 0
        creator = try container.decodeIfPresent(String.self, forKey: .creator)
        creatorAppID = Self.decodeLossyInt(from: container, forKey: .creator_app_id)
        consumerAppID = Self.decodeLossyInt(from: container, forKey: .consumer_app_id)
        fileSize = Self.decodeLossyInt64(from: container, forKey: .file_size)
        if let preview = try container.decodeIfPresent(String.self, forKey: .preview_url),
           !preview.isEmpty {
            previewURL = URL(string: preview)
        } else {
            previewURL = nil
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        timeCreated = Self.decodeLossyInt64(from: container, forKey: .time_created)
        timeUpdated = Self.decodeLossyInt64(from: container, forKey: .time_updated)
        visibility = Self.decodeLossyInt(from: container, forKey: .visibility)
        banned = Self.decodeLossyInt(from: container, forKey: .banned)
        banReason = try container.decodeIfPresent(String.self, forKey: .ban_reason)
        subscriptions = Self.decodeLossyInt(from: container, forKey: .subscriptions)
        favorited = Self.decodeLossyInt(from: container, forKey: .favorited)
        lifetimeSubscriptions = Self.decodeLossyInt(from: container, forKey: .lifetime_subscriptions)
        lifetimeFavorited = Self.decodeLossyInt(from: container, forKey: .lifetime_favorited)
        views = Self.decodeLossyInt(from: container, forKey: .views)
        tags = (try? container.decode([SteamWorkshopPublishedFileTag].self, forKey: .tags)) ?? []
    }

    private static func decodeLossyInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let string = try? container.decode(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }

    private static func decodeLossyInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Int64(value)
        }
        if let string = try? container.decode(String.self, forKey: key) {
            return Int64(string)
        }
        return nil
    }
}

struct SteamWorkshopBrowserCacheSnapshot: Codable {
    let fetchedAt: Date
    let items: [SteamWorkshopBrowserItem]
}

struct SteamWorkshopBrowseStubPage {
    let stubs: [SteamWorkshopBrowseStub]
    let hasMore: Bool
}

struct SteamWorkshopDiscoveryBrowseSnapshot {
    let browserItems: [SteamWorkshopBrowserItem]
    let browserState: SteamWorkshopBrowserLoadState
    let hasMoreBrowserItems: Bool
    let browserNextPage: Int
    let statusMessage: String
    let currentPageTitle: String
    let requestedURL: URL
    let browserQuery: String
    let currentWorkshopItemID: String?
    let selectedBrowserItem: SteamWorkshopBrowserItem?
    let prefetchedBrowserPageKeys: Set<String>
    let scrollOffsetY: CGFloat
}

struct SteamWorkshopBrowseStub: Equatable {
    let id: String
    let title: String?
    let author: String?
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let hasAdultContent: Bool
    let summary: String?
    let previewImageURL: URL?
}

struct SteamWorkshopDetailCacheSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
}

struct SteamWorkshopBundledRuntimeMetadata: Codable {
    let channel: String
    let version: String
    let releaseDate: String
    let notes: String
}
