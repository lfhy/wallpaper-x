import Foundation

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
