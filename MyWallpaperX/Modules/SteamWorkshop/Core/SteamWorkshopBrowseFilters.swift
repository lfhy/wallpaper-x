import Foundation

enum SteamWorkshopSource: String, CaseIterable, Identifiable {
    case featured
    case recent
    case subscribed
    case updated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .featured: return "最热门"
        case .recent: return "最新发布"
        case .subscribed: return "最多订阅"
        case .updated: return "最后更新"
        }
    }

    var browseFilter: String {
        switch self {
        case .featured: return "trend"
        case .recent: return "mostrecent"
        case .subscribed: return "totaluniquesubscribers"
        case .updated: return "lastupdated"
        }
    }

    var supportsTimeRange: Bool {
        self == .featured
    }
}

enum SteamWorkshopTrendingWindow: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case quarter
    case halfYear
    case year
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "今天"
        case .week: return "一周"
        case .month: return "30 天"
        case .quarter: return "三个月"
        case .halfYear: return "半年"
        case .year: return "一年"
        case .allTime: return "有史以来"
        }
    }

    var daysValue: String {
        switch self {
        case .today: return "1"
        case .week: return "7"
        case .month: return "30"
        case .quarter: return "90"
        case .halfYear: return "180"
        case .year: return "365"
        case .allTime: return "-1"
        }
    }
}

enum SteamWorkshopThemeFilter: String, CaseIterable, Identifiable {
    case all
    case abstract = "Abstract"
    case anime = "Anime"
    case animal = "Animal"
    case city = "City"
    case technology = "Technology"
    case landscape = "Landscape"
    case space = "Space"
    case scifi = "Sci-Fi"
    case cgi = "CGI"
    case cyberpunk = "Cyberpunk"
    case fantasy = "Fantasy"
    case game = "Game"
    case movie = "Movie"
    case music = "Music"
    case nature = "Nature"
    case relaxing = "Relaxing"
    case cartoon = "Cartoon"
    case cute = "Cute"
    case vehicle = "Vehicle"
    case girls = "Girls"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .abstract: return "抽象"
        case .anime: return "动漫"
        case .animal: return "动物"
        case .city: return "城市"
        case .technology: return "科技"
        case .landscape: return "风景"
        case .space: return "太空"
        case .scifi: return "科幻"
        case .cgi: return "CGI"
        case .cyberpunk: return "赛博"
        case .fantasy: return "奇幻"
        case .game: return "游戏"
        case .movie: return "影视"
        case .music: return "音乐"
        case .nature: return "自然"
        case .relaxing: return "治愈"
        case .cartoon: return "卡通"
        case .cute: return "可爱"
        case .vehicle: return "汽车"
        case .girls: return "人物"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopAgeRatingFilter: String, CaseIterable, Identifiable {
    case all
    case everyone = "Everyone"
    case mature = "Mature"
    case unspecified = "Unspecified"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部年龄"
        case .everyone: return "大众级"
        case .mature: return "成人级"
        case .unspecified: return "未指定"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopResolutionFilter: String, CaseIterable, Identifiable {
    case all
    case uhd4k = "3840 x 2160"
    case qhd = "2560 x 1440"
    case fhd = "1920 x 1080"
    case portrait4k = "2160 x 3840"
    case portrait2k = "1440 x 2560"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部分辨率"
        default: return rawValue
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case wallpaper = "Wallpaper"
    case scene = "Scene"
    case web = "Web"
    case application = "Application"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部分类"
        case .wallpaper: return "壁纸"
        case .scene: return "场景"
        case .web: return "网页"
        case .application: return "应用"
        }
    }

    var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopBrowserLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum SteamWorkshopAuthenticationPhase: Equatable {
    case credentials
    case awaitingGuardCode
    case authenticated
}

enum SteamWorkshopAuthSessionState: Equatable {
    case unknown
    case valid
    case expired
    case authenticating
}
