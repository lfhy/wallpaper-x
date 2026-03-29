//
//  WallpaperSelectionContext.swift
//  MyWallpaperX
//

enum WallpaperSelectionContext: Equatable {
    case category(Category)
    case tag(String)

    var displayTitle: String {
        switch self {
        case .category(.myWallpapers):
            return "我的壁纸"
        case .category(.favorites):
            return "特别喜爱"
        case .category(.recentlyUsed):
            return "最近使用"
        case .category(.tags):
            return "标签"
        case .category(.settings):
            return "设置"
        case .tag(let tag):
            return tag
        }
    }

    var isSettings: Bool {
        if case .category(.settings) = self {
            return true
        }
        return false
    }

    var scrollPersistenceKey: String {
        switch self {
        case .category(let category):
            switch category {
            case .myWallpapers:
                return "category.myWallpapers"
            case .favorites:
                return "category.favorites"
            case .recentlyUsed:
                return "category.recentlyUsed"
            case .tags:
                return "category.tags"
            case .settings:
                return "category.settings"
            }
        case .tag(let tag):
            return "tag.\(tag)"
        }
    }

    var importContext: ImportContext {
        switch self {
        case .category(.favorites):
            return .favorites
        case .tag(let tag):
            return .tag(tag)
        default:
            return .library
        }
    }

    var deletionScope: WallpaperRemovalScope? {
        switch self {
        case .category(.myWallpapers):
            return .library
        case .category(.recentlyUsed):
            return .recentlyUsed
        case .category(.favorites):
            return .favorites
        case .tag(let tag):
            return .tag(tag)
        default:
            return nil
        }
    }

    func sourceWallpapers(from manager: WallpaperManager) -> [VideoWallpaper] {
        switch self {
        case .category(.myWallpapers):
            return manager.wallpapers
        case .category(.favorites):
            return manager.favoriteWallpapers
        case .category(.recentlyUsed):
            return manager.recentlyUsedWallpapers
        case .category(.tags):
            return manager.wallpapers
        case .category(.settings):
            return []
        case .tag(let tag):
            return manager.wallpapers.filter { $0.tags.contains(tag) }
        }
    }

    func hasWallpapers(in manager: WallpaperManager) -> Bool {
        switch self {
        case .category(.myWallpapers), .category(.tags):
            return !manager.wallpapers.isEmpty
        case .category(.favorites):
            return manager.wallpapers.contains { $0.isFavorite }
        case .category(.recentlyUsed):
            return !manager.recentlyUsedWallpapers.isEmpty
        case .category(.settings):
            return false
        case .tag(let tag):
            return manager.wallpapers.contains { $0.tags.contains(tag) }
        }
    }
}

extension WallpaperManager {
    var currentSelectionContext: WallpaperSelectionContext {
        if let tag = selectedTag {
            return .tag(tag)
        }
        return .category(selectedCategory)
    }
}

extension SelectedItem {
    var selectionContext: WallpaperSelectionContext {
        switch self {
        case .category(let category):
            return .category(category)
        case .tag(let tag):
            return .tag(tag)
        }
    }

    init(selectionContext: WallpaperSelectionContext) {
        switch selectionContext {
        case .category(let category):
            self = .category(category)
        case .tag(let tag):
            self = .tag(tag)
        }
    }

    func apply(to manager: WallpaperManager) {
        switch self {
        case .category(let category):
            manager.selectCategory(category)
        case .tag(let tag):
            manager.selectTag(tag)
        }
    }

    mutating func applyTagRename(from oldTag: String, to newTag: String) -> Bool {
        guard case .tag(let selectedTag) = self, selectedTag == oldTag else {
            return false
        }
        self = .tag(newTag)
        return true
    }

    mutating func applyTagRemoval(_ tag: String) -> Bool {
        guard case .tag(let selectedTag) = self, selectedTag == tag else {
            return false
        }
        self = .category(.tags)
        return true
    }
}
