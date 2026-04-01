//
//  SILService.swift
//  MyWallpaperX — Modules/StaticImageLibrary/Core
//
//  图片壁纸库核心服务。
//  依赖：Models、Shared（无）。不依赖 VideoLibrary 任何类型。
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

// MARK: - 数据模型

struct SILWallpaper: Identifiable, Codable, Hashable {
    var id: String
    var path: String
    var title: String
    var fileSize: Int64?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var tags: [String]
    var lastUsed: Date
    var addedAt: Date

    /// 图片宽高比（width/height），无尺寸信息时返回 16/9 作为默认值
    var aspectRatio: CGFloat {
        guard let w = pixelWidth, let h = pixelHeight, h > 0 else { return 16.0 / 9.0 }
        return CGFloat(w) / CGFloat(h)
    }

    init(path: String) {
        self.id = UUID().uuidString
        self.path = path
        self.title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64)
        // 从图片文件读取像素尺寸（不解码像素，只读 metadata，极快）
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            self.pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
            self.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        } else {
            self.pixelWidth  = nil
            self.pixelHeight = nil
        }
        self.tags = []
        self.lastUsed = Date.distantPast
        self.addedAt = Date()
    }
}

enum SILSortMode: String, CaseIterable, Codable {
    case none
    case name
    case lastUsed
    case fileSize
    case addedAt

    var displayName: String {
        switch self {
        case .none:     return "默认顺序"
        case .name:     return "文件名称"
        case .lastUsed: return "最近使用"
        case .fileSize: return "文件大小"
        case .addedAt:  return "添加时间"
        }
    }
}

struct SILSortState: Codable, Equatable {
    var mode: SILSortMode = .none
    var ascending: Bool = true
}

// MARK: - SILService

final class SILService: ObservableObject {

    static let shared = SILService()

    @Published var wallpapers: [SILWallpaper] = []
    @Published var selectedID: String? = nil
    @Published var selectedIDs: Set<String> = []
    @Published var isMultiSelectMode: Bool = false
    @Published var gridZoomOffset: Int = 0
    @Published var searchQuery: String = ""
    @Published var sortState: SILSortState = SILSortState()
    /// 当前网格实际列数，由 SILGridContainerView 在 layout 时写入，供方向键导航使用
    var visibleGridColumnCount: Int = 4
    /// 图片库专属标签列表（与视频库 WallpaperManager.tags 完全独立）
    @Published var silTags: [String] = []
    /// 当前激活的侧边栏标签上下文；nil 表示「我的图片」全库，非 nil 表示标签子视图
    /// 由 SILToolbarController 在收到 staticImageLibraryModeDidChange 通知时维护
    var currentContextTag: String? = nil

    private let persistenceURL: URL
    private let zoomOffsetKey = "SILGridZoomOffset"
    private let sortStateKey  = "SILSortState"
    private let silTagsKey    = "SILTags"

    /// 供外部（如重置功能）访问持久化文件路径
    var silPersistenceURL: URL { persistenceURL }

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.persistenceURL = appSupport.appendingPathComponent("sil_wallpapers.json")
        load()
        gridZoomOffset = UserDefaults.standard.integer(forKey: zoomOffsetKey)
        if let data = UserDefaults.standard.data(forKey: sortStateKey),
           let state = try? JSONDecoder().decode(SILSortState.self, from: data) {
            sortState = state
        }
        if let saved = UserDefaults.standard.stringArray(forKey: silTagsKey) {
            silTags = saved
        }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([SILWallpaper].self, from: data) else { return }
        // 对旧数据补读像素尺寸（新导入的已在 init 时读取）
        wallpapers = decoded.map { w in
            guard w.pixelWidth == nil || w.pixelHeight == nil else { return w }
            var updated = w
            if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: w.path) as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                updated.pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
                updated.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            }
            return updated
        }
        // 如果有数据被补充，异步保存
        let needsSave = decoded.contains { $0.pixelWidth == nil || $0.pixelHeight == nil }
        if needsSave {
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.save() }
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(wallpapers) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    func saveZoomOffset() {
        UserDefaults.standard.set(gridZoomOffset, forKey: zoomOffsetKey)
    }

    func saveSortState() {
        if let data = try? JSONEncoder().encode(sortState) {
            UserDefaults.standard.set(data, forKey: sortStateKey)
        }
    }

    func saveSILTags() {
        UserDefaults.standard.set(silTags, forKey: silTagsKey)
    }

    // MARK: - 图片专属标签 CRUD

    /// 新建图片标签，名称去空白后不能为空且不能重复，成功返回规范化名称
    @discardableResult
    func createSILTag(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !silTags.contains(trimmed) else { return nil }
        silTags.append(trimmed)
        saveSILTags()
        return trimmed
    }

    /// 重命名图片标签，同时更新所有壁纸上的标签引用，返回新名称
    @discardableResult
    func renameSILTag(_ oldName: String, to newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName, !silTags.contains(trimmed) else { return nil }
        guard let idx = silTags.firstIndex(of: oldName) else { return nil }
        silTags[idx] = trimmed
        // 同步更新壁纸上的标签引用
        for i in wallpapers.indices {
            if let tagIdx = wallpapers[i].tags.firstIndex(of: oldName) {
                wallpapers[i].tags[tagIdx] = trimmed
            }
        }
        saveSILTags()
        save()
        return trimmed
    }

    /// 删除图片标签，同时从所有壁纸上移除该标签引用
    func deleteSILTag(_ name: String) {
        silTags.removeAll { $0 == name }
        for i in wallpapers.indices {
            wallpapers[i].tags.removeAll { $0 == name }
        }
        saveSILTags()
        save()
    }

    /// 拖拽排序后保存新顺序（只允许已存在的标签，不新增也不删除）
    func reorderSILTags(_ newOrder: [String]) {
        let existing = Set(silTags)
        let filtered = newOrder.filter { existing.contains($0) }
        guard filtered != silTags else { return }
        silTags = filtered
        saveSILTags()
    }

    /// 给选中的壁纸添加标签（单选/多选均支持），完成后自动退出多选模式
    func addSILTag(_ tag: String, toSelected ids: Set<String>) {
        guard silTags.contains(tag) else { return }
        for i in wallpapers.indices where ids.contains(wallpapers[i].id) {
            if !wallpapers[i].tags.contains(tag) {
                wallpapers[i].tags.append(tag)
            }
        }
        save()
        clearSelectionState()
    }

    /// 当前选中壁纸的有效 ID 集合（多选模式用 selectedIDs，单选模式用 selectedID）
    var effectiveSelectedIDs: Set<String> {
        if isMultiSelectMode {
            return selectedIDs
        } else if let id = selectedID {
            return Set([id])
        } else {
            return []
        }
    }

    /// 同 effectiveSelectedIDs，用不同名称避免 MainWindowCoordinator 中的类型推断歧义
    var silSelectedIDs: Set<String> {
        effectiveSelectedIDs
    }

    /// 是否有选中（供 MainWindowCoordinator 用，避免 effectiveSelectedIDs 的类型歧义）
    var hasAnySelection: Bool {
        if isMultiSelectMode { return !selectedIDs.isEmpty }
        return selectedID != nil
    }

    /// 某标签下的壁纸列表
    func wallpapers(forSILTag tag: String) -> [SILWallpaper] {
        wallpapers.filter { $0.tags.contains(tag) }
    }

    // MARK: - 计算属性

    var sortedWallpapers: [SILWallpaper] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [SILWallpaper]
        if query.isEmpty {
            filtered = wallpapers
        } else {
            filtered = wallpapers.filter {
                $0.title.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }
        guard sortState.mode != .none else { return filtered }
        return filtered.sorted { a, b in
            let asc = sortState.ascending
            switch sortState.mode {
            case .none:     return false
            case .name:     return asc ? a.title < b.title : a.title > b.title
            case .lastUsed: return asc ? a.lastUsed < b.lastUsed : a.lastUsed > b.lastUsed
            case .fileSize:
                let as_ = a.fileSize ?? 0; let bs = b.fileSize ?? 0
                return asc ? as_ < bs : as_ > bs
            case .addedAt:  return asc ? a.addedAt < b.addedAt : a.addedAt > b.addedAt
            }
        }
    }

    var currentActiveWallpaperPath: String? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }

    // MARK: - 选择

    func setSingleSelection(_ id: String) {
        guard !isMultiSelectMode else { return }
        selectedID = id
    }

    func replaceMultiSelection(with ids: Set<String>) {
        selectedIDs = ids
    }

    func selectAll() {
        selectedIDs = Set(sortedWallpapers.map(\.id))
    }

    func deselectAll() {
        selectedIDs = []
    }

    func clearSingleSelection() {
        selectedID = nil
    }

    func enterMultiSelectMode() {
        isMultiSelectMode = true
        selectedIDs = []
        selectedID = nil
    }

    func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedIDs = []
    }

    /// 切换列表或执行批量操作后统一调用，效果与视频库 clearSelectionState() 一致
    func clearSelectionState() {
        isMultiSelectMode = false
        selectedIDs = []
        selectedID = nil
    }

    func moveSingleSelectionByArrowKey(_ keyCode: UInt16) {
        guard !isMultiSelectMode else { return }
        let list = sortedWallpapers
        guard !list.isEmpty else { return }
        guard let current = selectedID, let idx = list.firstIndex(where: { $0.id == current }) else {
            selectedID = list.first?.id
            return
        }
        let cols = max(1, visibleGridColumnCount)
        let newIdx: Int
        switch keyCode {
        case 123: newIdx = max(0, idx - 1)                    // ←
        case 124: newIdx = min(list.count - 1, idx + 1)       // →
        case 125: newIdx = min(list.count - 1, idx + cols)    // ↓
        case 126: newIdx = max(0, idx - cols)                 // ↑
        default: return
        }
        selectedID = list[newIdx].id
    }

    // MARK: - 导入

    static var allowedUTTypes: [UTType] {
        [.jpeg, .png, .heic, .heif, .tiff, .bmp, .gif, 
         UTType("public.avif") ?? .image,
         UTType(filenameExtension: "webp") ?? .image]
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return allowedUTTypes.contains { type.conforms(to: $0) }
    }

    func importImages(from urls: [URL], presentingIn window: NSWindow? = nil) {
        var fileURLs: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator where Self.isSupportedImage(fileURL) {
                        fileURLs.append(fileURL)
                    }
                }
            } else if Self.isSupportedImage(url) {
                fileURLs.append(url)
            }
        }
        let requestedCount = fileURLs.count
        let existingPaths = Set(wallpapers.map(\.path))
        var added = 0
        var duplicateCount = 0
        var missingCount = 0
        for url in fileURLs {
            guard fm.fileExists(atPath: url.path) else { missingCount += 1; continue }
            
            if let index = wallpapers.firstIndex(where: { normalizedPath($0.path) == normalizedPath(url.path) }) {
                // 如果文件已存在于总库，检查是否需要补充当前标签索引
                if let tag = currentContextTag {
                    if !wallpapers[index].tags.contains(tag) {
                        wallpapers[index].tags.append(tag)
                        added += 1 // 视为成功"索引"到当前标签
                    }
                }
                duplicateCount += 1
                continue
            }
            
            var newWallpaper = SILWallpaper(path: url.path)
            if let tag = currentContextTag {
                newWallpaper.tags.append(tag)
            }
            wallpapers.append(newWallpaper)
            added += 1
        }

        func normalizedPath(_ path: String) -> String {
            URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        }
        if added > 0 { save() }
        // 构建结果弹窗
        var lines: [String] = [
            "总选择：\(requestedCount) 个",
            "新增导入：\(added) 个"
        ]
        let skipped = requestedCount - added - duplicateCount - missingCount
        if duplicateCount > 0 { lines.append("\(duplicateCount) 个文件已存在于列表中") }
        if missingCount > 0  { lines.append("\(missingCount) 个文件不存在") }
        if skipped > 0       { lines.append("未处理：\(skipped) 个") }
        let alert = makeAppAlert(title: "导入结果", message: lines.joined(separator: "\n"))
        presentAppAlert(alert, in: window ?? appModalHostWindow())
    }

    func importFromPanel(presentingIn window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.allowedUTTypes
        panel.title = "选择图片壁纸"
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                self?.importImages(from: panel.urls, presentingIn: window)
            }
        } else {
            guard panel.runModal() == .OK else { return }
            importImages(from: panel.urls, presentingIn: nil)
        }
    }

    // MARK: - 删除

    /// 从总库移除（同时清除所有标签引用），删除前先找临近项作为新选中目标
    func remove(ids: Set<String>) {
        let nextID = resolveNextSelectionID(removingIDs: ids)
        wallpapers.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        selectedID = nextID
        if isMultiSelectMode { isMultiSelectMode = false }
        save()
    }

    /// 仅从指定标签中移除索引，不删除总库记录，完成后自动退出多选模式
    func removeFromSILTag(_ tag: String, ids: Set<String>) {
        // 标签页移除只是去掉索引，不影响总库，无需跳选中，直接清掉即可
        for i in wallpapers.indices where ids.contains(wallpapers[i].id) {
            wallpapers[i].tags.removeAll { $0 == tag }
        }
        clearSelectionState()
        save()
    }

    /// 删除前在当前排序列表里找到被删项的临近项（优先取后继，否则取前驱）
    private func resolveNextSelectionID(removingIDs: Set<String>) -> String? {
        guard !isMultiSelectMode, let currentID = selectedID,
              removingIDs.contains(currentID) else { return selectedID }
        let list = sortedWallpapers
        guard let idx = list.firstIndex(where: { $0.id == currentID }) else { return nil }
        let next = list[(idx + 1)...].first { !removingIDs.contains($0.id) }
        let prev = list[..<idx].last  { !removingIDs.contains($0.id) }
        return (next ?? prev)?.id
    }

    // MARK: - 信息

    func detailInfoText(for wallpaper: SILWallpaper, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: wallpaper.path)
            var lines: [String] = []
            lines.append("文件名：\(url.lastPathComponent)")
            lines.append("路径：\(wallpaper.path)")
            if let size = wallpaper.fileSize {
                let mb = Double(size) / 1_048_576
                lines.append(String(format: "大小：%.2f MB", mb))
            }
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                if w > 0 && h > 0 { lines.append("尺寸：\(w) × \(h)") }
            }
            let fmt = DateFormatter()
            fmt.dateStyle = .medium; fmt.timeStyle = .short
            lines.append("添加时间：\(fmt.string(from: wallpaper.addedAt))")
            if wallpaper.lastUsed > Date.distantPast {
                lines.append("最近使用：\(fmt.string(from: wallpaper.lastUsed))")
            }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
    }
}
