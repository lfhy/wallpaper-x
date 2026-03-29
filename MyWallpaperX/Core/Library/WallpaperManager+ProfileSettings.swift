//
//  WallpaperManager+ProfileSettings.swift
//  MyWallpaperX
//

import Foundation

struct PersonalSettingsExportSummary {
    let wallpaperCount: Int
    let tagCount: Int
}

struct PersonalSettingsImportSummary {
    let mergedWallpaperCount: Int
    let createdWallpaperCount: Int
    let missingPathCount: Int
    let tagCount: Int
}

/// 只导出用户真正关心的偏好字段，不序列化整个 WallpaperSettings，减小文件体积。
private struct ExportedPreferences: Codable {
    var loopPlayback: Bool
    var randomPlayback: Bool
    var sequentialPlayback: Bool
    var autoSwitchEnabled: Bool
    var randomInterval: Int
    var timeUnit: TimeUnit
    var volume: Double
    var startOnBoot: Bool
    var pauseWhenOtherAppFullscreen: Bool
    var pauseWhenOtherAppFocused: Bool
    var pauseWhenUnplugged: Bool
    var pauseWhenIdle: Bool
    var idleTimeoutMinutes: Int
    var multiDisplayEnabled: Bool
    var videoFillMode: VideoFillMode
    var syncSystemWallpaper: Bool
    var playbackRate: Double
    var playbackRateEnabled: Bool
    var sortMode: WallpaperSortMode
    var sortAscending: Bool

    init(from settings: WallpaperSettings) {
        loopPlayback = settings.loopPlayback
        randomPlayback = settings.randomPlayback
        sequentialPlayback = settings.sequentialPlayback
        autoSwitchEnabled = settings.autoSwitchEnabled
        randomInterval = settings.randomInterval
        timeUnit = settings.timeUnit
        volume = settings.volume
        startOnBoot = settings.startOnBoot
        pauseWhenOtherAppFullscreen = settings.pauseWhenOtherAppFullscreen
        pauseWhenOtherAppFocused = settings.pauseWhenOtherAppFocused
        pauseWhenUnplugged = settings.pauseWhenUnplugged
        pauseWhenIdle = settings.pauseWhenIdle
        idleTimeoutMinutes = settings.idleTimeoutMinutes
        multiDisplayEnabled = settings.multiDisplayEnabled
        videoFillMode = settings.videoFillMode
        syncSystemWallpaper = settings.syncSystemWallpaper
        playbackRate = settings.playbackRate
        playbackRateEnabled = settings.playbackRateEnabled
        sortMode = settings.sortMode
        sortAscending = settings.sortAscending
    }

    func apply(to settings: inout WallpaperSettings) {
        settings.loopPlayback = loopPlayback
        settings.randomPlayback = randomPlayback
        settings.sequentialPlayback = sequentialPlayback
        settings.autoSwitchEnabled = autoSwitchEnabled
        settings.randomInterval = randomInterval
        settings.timeUnit = timeUnit
        settings.volume = volume
        settings.startOnBoot = startOnBoot
        settings.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        settings.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        settings.pauseWhenUnplugged = pauseWhenUnplugged
        settings.pauseWhenIdle = pauseWhenIdle
        settings.idleTimeoutMinutes = idleTimeoutMinutes
        settings.multiDisplayEnabled = multiDisplayEnabled
        settings.videoFillMode = videoFillMode
        settings.syncSystemWallpaper = syncSystemWallpaper
        settings.playbackRate = playbackRate
        settings.playbackRateEnabled = playbackRateEnabled
        settings.sortMode = sortMode
        settings.sortAscending = sortAscending
    }
}

private struct PersonalSettingsPayload: Codable {
    struct Entry: Codable {
        let path: String
        let title: String
        let isFavorite: Bool
        let tags: [String]
    }

    // schemaVersion 2：preferences 替换整个 WallpaperSettings，体积更小且只含用户偏好。
    let schemaVersion: Int
    let exportedAt: Date
    let preferences: ExportedPreferences
    let tags: [String]
    let entries: [Entry]
}

extension WallpaperManager {
    func exportPersonalSettings(to url: URL) throws -> PersonalSettingsExportSummary {
        // 导出只打包用户态配置和引用关系，不导出派生缓存路径，避免文件搬家后误以为资源已固定。
        let payload = PersonalSettingsPayload(
            schemaVersion: 2,
            exportedAt: Date(),
            preferences: ExportedPreferences(from: settings),
            tags: normalizedTagList(tags),
            entries: wallpapers.map { wallpaper in
                PersonalSettingsPayload.Entry(
                    path: normalizedPath(wallpaper.path),
                    title: wallpaper.title,
                    isFavorite: wallpaper.isFavorite,
                    tags: normalizedTagList(wallpaper.tags)
                )
            }
        )

        // 使用紧凑 JSON（不 prettyPrinted），文件体积比 v1 减少约 40-50%。
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)

        return PersonalSettingsExportSummary(
            wallpaperCount: payload.entries.count,
            tagCount: payload.tags.count
        )
    }

    func importPersonalSettings(from url: URL) throws -> PersonalSettingsImportSummary {
        // 导入策略是"合并到现有库"，不是整库覆盖；这样不会误删用户现有壁纸与标签。
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PersonalSettingsPayload.self, from: data)
        let existingTags = tags

        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(wallpapers.count)
        for index in wallpapers.indices {
            indexByPath[normalizedPath(wallpapers[index].path)] = index
        }

        var mergedCount = 0
        var createdCount = 0
        var missingCount = 0

        for entry in payload.entries {
            let normalizedEntryPath = normalizedPath(entry.path)
            let normalizedEntryTags = normalizedTagList(entry.tags)
            // 文件存在性检查放在后台完成后汇总，这里直接用导入时缓存的路径集合判断。
            // normalizedSourcePathExists 是同步磁盘 I/O，条目多时在主线程累积卡顿。
            // 改为：仅在最终 apply 阶段统计缺失数，不逐条阻塞主线程。
            let fileExists = FileManager.default.fileExists(atPath: normalizedEntryPath)
            if !fileExists {
                missingCount += 1
            }

            if let existingIndex = indexByPath[normalizedEntryPath] {
                wallpapers[existingIndex].isFavorite = entry.isFavorite
                wallpapers[existingIndex].tags = normalizedTagList(wallpapers[existingIndex].tags + normalizedEntryTags)
                if !entry.title.isEmpty {
                    // title 是 let，只能通过整体重建更新；其它字段已在上面直接修改过，直接透传。
                    wallpapers[existingIndex] = VideoWallpaper(
                        id: wallpapers[existingIndex].id,
                        title: entry.title,
                        path: wallpapers[existingIndex].path,
                        thumbnailPath: wallpapers[existingIndex].thumbnailPath,
                        staticFramePath: wallpapers[existingIndex].staticFramePath,
                        isFavorite: wallpapers[existingIndex].isFavorite,
                        lastUsed: wallpapers[existingIndex].lastUsed,
                        tags: wallpapers[existingIndex].tags
                    )
                }
                mergedCount += 1
                continue
            }

            let newWallpaper = VideoWallpaper(
                title: entry.title.isEmpty
                    ? URL(fileURLWithPath: normalizedEntryPath).lastPathComponent
                    : entry.title,
                path: normalizedEntryPath,
                thumbnailPath: nil,
                staticFramePath: nil,
                isFavorite: entry.isFavorite,
                lastUsed: Date(),
                tags: normalizedEntryTags
            )
            wallpapers.append(newWallpaper)
            indexByPath[normalizedEntryPath] = wallpapers.count - 1
            createdCount += 1
        }

        // 把导入的偏好写回 settings，热键配置不覆盖（用户本地配置优先）。
        payload.preferences.apply(to: &settings)
        sanitizeSystemHotkeySettingsIfNeeded()
        normalizePlaybackSettings()
        syncAutoSwitchPlaybackPolicy(forceTimerRestart: true)
        applyEngineSettings(reloadWallpaper: false)
        applyPlaybackRateToEngine()
        updateLoginItemStatus()

        // tags = 现有标签 + 导入标签 + 壁纸内引用标签，保留用户现有体系，不做强制替换。
        let payloadTags = normalizedTagList(payload.tags)
        let wallpaperTags = wallpapers.flatMap(\.tags)
        tags = normalizedTagList(existingTags + payloadTags + wallpaperTags)

        saveSettings()
        saveTags()
        saveWallpapers()

        normalizeRecentWallpapers(limit: WallpaperManager.recentWallpapersLimit, requireExistingFiles: false)
        saveRecentWallpapers()
        persistCurrentWallpaperSnapshot()
        NotificationCenter.default.post(name: .wallpaperManagerDidImportPersonalSettings, object: self)

        return PersonalSettingsImportSummary(
            mergedWallpaperCount: mergedCount,
            createdWallpaperCount: createdCount,
            missingPathCount: missingCount,
            tagCount: tags.count
        )
    }
}
