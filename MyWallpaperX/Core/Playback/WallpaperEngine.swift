//
//  WallpaperEngine.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//


import Foundation
import AVFoundation
import AppKit
import CoreGraphics

public final class WallpaperEngine: NSObject {
    public static let shared = WallpaperEngine()
    public static let playbackFailedNotification = Notification.Name("WallpaperEnginePlaybackFailedNotification")
    public static let playbackEndedNotification = Notification.Name("WallpaperEnginePlaybackEndedNotification")

    // 一个 display 对应一个 daemon session；后面所有播放、暂停、换壁纸都围绕这个会话表展开。
    final class DisplayDaemonSession {
        let displayID: CGDirectDisplayID
        let process: Process
        let inputPipe: Pipe
        let outputPipe: Pipe
        let errorPipe: Pipe
        var outputBuffer = Data()
        var nextRequestID = 0
        var latestRequestedPlayRequestID: Int?
        var latestAcceptedPlayRequestID: Int?
        var latestReadyPlayRequestID: Int?
        var launched = false

        // 退避计数：连续崩溃次数，成功播放后清零。
        var consecutiveCrashCount: Int = 0

        init(displayID: CGDirectDisplayID, process: Process, inputPipe: Pipe, outputPipe: Pipe, errorPipe: Pipe) {
            self.displayID = displayID
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
        }
    }

    // 每个 display 的退避计数独立维护，session 重建时继承，成功后归零。
    var displayCrashCounts: [CGDirectDisplayID: Int] = [:]

    var displaySessions: [CGDirectDisplayID: DisplayDaemonSession] = [:]
    var currentWallpaper: VideoWallpaper?
    var displayIDs: [CGDirectDisplayID] = []
    var wasPlayingBeforeSleep = true
    var screenLocked = false
    var visibilityReductionActive = false
    var playbackPaused = false
    var reducedPerformanceMode = false
    var targetPlaybackRate: Float = 1.0
    var currentVolumeNormalized: Float = 0.5
    var currentVideoFillMode = VideoFillMode.aspectFill.rawValue
    var currentMultiDisplayEnabled = true
    var currentShouldLoopCurrentItem = false

    var pauseWhenOtherAppFocused = true
    var pauseWhenOtherAppFullscreen = true
    var pauseWhenUnplugged = false
    var pauseWhenIdle = false
    var idleMonitorTimer: DispatchSourceTimer?
    var idleMonitorReady = false  // 定时器触发过至少一次才允许评估 idle 状态，防止开启开关瞬间误暂停
    var idleTimeoutMinutes = 10

    var systemSleeping = false
    var displaysSleeping = false
    var wasPlayingBeforeSystemSleep = false
    var wasPlayingBeforeDisplaySleep = false
    var lastClickTime: TimeInterval = 0
    let clickDebounceInterval: TimeInterval = 0.3
    var lastFailureVideoPath: String?
    var lastFailureAt: TimeInterval = 0
    var lastEndedVideoPath: String?
    var lastEndedAt: TimeInterval = 0
    var suppressFullscreenPauseUntil: TimeInterval = 0
    var pendingPlaybackStateRefreshWorkItem: DispatchWorkItem?
    var pendingPlaybackStateRefreshDeadline: CFTimeInterval?
    var lastPlaybackStateEvaluationAt: CFTimeInterval = 0
    let playbackStateEvaluationMinInterval: TimeInterval = 0.10
    var powerStateFallbackTimer: DispatchSourceTimer?
    var lastObservedOnBattery: Bool?
    var lastFullscreenSpaceState: Bool?
    var lastFullscreenSpaceStateAt: CFTimeInterval = 0
    let fullscreenSpaceStateCacheTTL: TimeInterval = 0.25

    override init() {
        super.init()
        setupNotifications()
        scanDisplays()
    }

    public func setWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool,
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int
    ) {
        // 对外统一入口只做节流后的切换，避免上层绕开状态机直接改 daemon。
        applyWallpaper(
            wallpaper,
            multiDisplayEnabled: multiDisplayEnabled,
            videoFillMode: videoFillMode,
            shouldLoopCurrentItem: shouldLoopCurrentItem,
            pauseWhenOtherAppFocused: pauseWhenOtherAppFocused,
            pauseWhenOtherAppFullscreen: pauseWhenOtherAppFullscreen,
            pauseWhenUnplugged: pauseWhenUnplugged,
            pauseWhenIdle: pauseWhenIdle,
            idleTimeoutMinutes: idleTimeoutMinutes,
            shouldDebounce: true
        )
    }

    func applyWallpaper(
        _ wallpaper: VideoWallpaper,
        multiDisplayEnabled: Bool,
        videoFillMode: String,
        shouldLoopCurrentItem: Bool,
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int,
        shouldDebounce: Bool
    ) {
        let currentTime = CACurrentMediaTime()
        if shouldDebounce, currentTime - lastClickTime <= clickDebounceInterval {
            return
        }
        lastClickTime = currentTime

        let previousNormalizedPath = currentWallpaper.map { normalizedPath($0.path) }
        let incomingNormalizedPath = normalizedPath(wallpaper.path)
        let previousVideoFillMode = currentVideoFillMode
        let previousMultiDisplayEnabled = currentMultiDisplayEnabled
        let previousShouldLoopCurrentItem = currentShouldLoopCurrentItem

        // 先更新内存态，再决定是否复用现有 daemon session 或下发新的 play 命令。
        currentWallpaper = wallpaper
        currentVideoFillMode = videoFillMode
        currentMultiDisplayEnabled = multiDisplayEnabled
        currentShouldLoopCurrentItem = shouldLoopCurrentItem
        self.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        self.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        self.pauseWhenUnplugged = pauseWhenUnplugged
        self.pauseWhenIdle = pauseWhenIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        refreshPowerStateFallbackMonitoring()
        refreshIdleMonitoring()

        scanDisplays()
        let targetDisplayIDs = multiDisplayEnabled ? displayIDs : [displayIDs.first].compactMap { $0 }
        let existingDisplayIDs = Set(displaySessions.keys)
        let targetDisplayIDSet = Set(targetDisplayIDs)
        let noObsoleteDisplaySessions = existingDisplayIDs.isSubset(of: targetDisplayIDSet)
        let targetSessionsReady = !targetDisplayIDs.isEmpty
            && targetDisplayIDs.allSatisfy { displaySessions[$0]?.process.isRunning == true }

        let isSameWallpaperRequest = previousNormalizedPath == incomingNormalizedPath
        let isConfigurationUnchanged =
            previousVideoFillMode == videoFillMode
            && previousMultiDisplayEnabled == multiDisplayEnabled
            && previousShouldLoopCurrentItem == shouldLoopCurrentItem

        // 同一壁纸、同一配置且 session 仍然有效时，直接刷新播放状态，不重建播放链路。
        if isSameWallpaperRequest
            && isConfigurationUnchanged
            && noObsoleteDisplaySessions
            && targetSessionsReady {
            requestPlaybackStateEvaluation(immediate: true)
            return
        }

        for displayID in targetDisplayIDs {
            guard let session = ensureSession(for: displayID) else { continue }
            sendPlayCommand(
                for: wallpaper.path,
                framePath: wallpaper.staticFramePath,
                fillMode: videoFillMode,
                shouldLoopCurrentItem: shouldLoopCurrentItem,
                to: session
            )
        }

        let obsoleteDisplayIDs = Set(displaySessions.keys).subtracting(targetDisplayIDs)
        for displayID in obsoleteDisplayIDs {
            terminateSession(for: displayID)
        }

        requestPlaybackStateEvaluation(immediate: true)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    public func updateSettings(
        pauseWhenOtherAppFocused: Bool,
        pauseWhenOtherAppFullscreen: Bool,
        pauseWhenUnplugged: Bool,
        pauseWhenIdle: Bool,
        idleTimeoutMinutes: Int
    ) {
        // 这里只更新暂停策略和闲置阈值，避免把设置层的其它变更混进引擎热路径。
        self.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        self.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        self.pauseWhenUnplugged = pauseWhenUnplugged
        self.pauseWhenIdle = pauseWhenIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        refreshPowerStateFallbackMonitoring()
        refreshIdleMonitoring()

        requestPlaybackStateEvaluation(immediate: true)
    }

    public func stopPlayback() {
        for displayID in Array(displaySessions.keys) {
            terminateSession(for: displayID)
        }
    }

    public func cleanup() {
        // 退出或重建时必须清掉定时器和挂起评估，否则旧状态会继续回写。
        powerStateFallbackTimer?.cancel()
        powerStateFallbackTimer = nil
        idleMonitorTimer?.cancel()
        idleMonitorTimer = nil
        pendingPlaybackStateRefreshWorkItem?.cancel()
        pendingPlaybackStateRefreshWorkItem = nil
        pendingPlaybackStateRefreshDeadline = nil
        stopPlayback()
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        displayIDs.removeAll()
        currentWallpaper = nil
    }

    public func pauseAllPlayers() {
        assert(Thread.isMainThread, "pauseAllPlayers must be called on main thread")
        if playbackPaused { return }

        // 统一给所有正在运行的 daemon 下发 pause，保持引擎状态机单一。
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "pause", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, requestID: nil), to: session)
        }
        playbackPaused = true
    }

    public func resumeAllPlayers() {
        assert(Thread.isMainThread, "resumeAllPlayers must be called on main thread")
        if !playbackPaused { return }

        // 恢复时统一带回当前播放速率，避免不同 session 恢复节奏不一致。
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: targetPlaybackRate, requestID: nil), to: session)
        }
        playbackPaused = false
    }

    public func setVolume(_ volume: Float) {
        let normalizedVolume = min(max(volume, 0), 100) / 100
        currentVolumeNormalized = normalizedVolume

        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setVolume", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: normalizedVolume, playbackRate: nil, requestID: nil), to: session)
        }
    }

    public func setFillMode(_ fillMode: String) {
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setFillMode", videoPath: nil, framePath: nil, fillMode: fillMode, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, requestID: nil), to: session)
        }
    }

    public func setLoopCurrentItem(_ shouldLoop: Bool) {
        // 只更新循环状态，不重载视频，避免切换自动切换开关时画面闪烁。
        // 不做去重，确保每次开关操作都能可靠送达 daemon。
        currentShouldLoopCurrentItem = shouldLoop
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "setLoop", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: shouldLoop, volume: nil, playbackRate: nil, requestID: nil), to: session)
        }
    }

    public func setPlaybackRate(_ rate: Float) {
        // 速率变化只在未暂停时立即下发 resume 命令更新速度；暂停时只更新 targetPlaybackRate，恢复时自动生效。
        let clampedRate = max(0.25, min(2.0, rate))
        targetPlaybackRate = clampedRate
        guard !playbackPaused else { return }
        for session in displaySessions.values where session.process.isRunning {
            send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: clampedRate, requestID: nil), to: session)
        }
    }

    public func isPlaying() -> Bool {
        !playbackPaused && displaySessions.values.contains { $0.process.isRunning }
    }

    public func togglePlayback() {
        if playbackPaused {
            resumeAllPlayers()
        } else {
            pauseAllPlayers()
        }
    }

    public func refreshPlaybackState() {
        // 状态评估只走统一入口，避免 UI / 系统通知各自直接改 pause 状态。
        requestPlaybackStateEvaluation(immediate: true)
    }

    public func getCurrentWallpaper() -> VideoWallpaper? {
        currentWallpaper
    }

    private func ensureSession(for displayID: CGDirectDisplayID) -> DisplayDaemonSession? {
        if let session = displaySessions[displayID], session.process.isRunning {
            return session
        }

        // session 失效后先清理旧进程，再按当前显示器拓扑重新拉起 helper。
        terminateSession(for: displayID)

        guard let helperURL = helperExecutableURL() else {
            return nil
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--display-id", String(displayID)]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let session = DisplayDaemonSession(displayID: displayID, process: process, inputPipe: inputPipe, outputPipe: outputPipe, errorPipe: errorPipe)
        attachReaders(for: session)

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let previousSession = self.displaySessions[displayID]
                if previousSession === session {
                    self.displaySessions.removeValue(forKey: displayID)
                }
                self.cleanupSessionIO(session)

                guard self.shouldMaintainSession(for: displayID),
                      let currentWallpaper = self.currentWallpaper else {
                    return
                }

                // 指数退避：连续崩溃时延迟重建，防止损坏视频/权限问题导致 CPU 热循环。
                // 延迟序列：0s → 1s → 2s → 4s → 8s → 16s → 30s（封顶）。
                let crashCount = self.displayCrashCounts[displayID, default: 0]
                self.displayCrashCounts[displayID] = crashCount + 1
                let delay: TimeInterval = crashCount == 0
                    ? 0
                    : min(pow(2.0, Double(crashCount - 1)), 30.0)

                let rebuild = { [weak self] in
                    guard let self else { return }
                    // helper 异常退出后，只在当前播放项仍有效时重放，避免把旧请求重新灌回去。
                    self.applyWallpaper(
                        currentWallpaper,
                        multiDisplayEnabled: self.currentMultiDisplayEnabled,
                        videoFillMode: self.currentVideoFillMode,
                        shouldLoopCurrentItem: self.currentShouldLoopCurrentItem,
                        pauseWhenOtherAppFocused: self.pauseWhenOtherAppFocused,
                        pauseWhenOtherAppFullscreen: self.pauseWhenOtherAppFullscreen,
                        pauseWhenUnplugged: self.pauseWhenUnplugged,
                        pauseWhenIdle: self.pauseWhenIdle,
                        idleTimeoutMinutes: self.idleTimeoutMinutes,
                        shouldDebounce: false
                    )
                }

                if delay <= 0 {
                    rebuild()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: rebuild)
                }
            }
        }

        do {
            try process.run()
            displaySessions[displayID] = session
            return session
        } catch {
            cleanupSessionIO(session)
            return nil
        }
    }

    private func helperExecutableURL() -> URL? {
        // helper 位于 bundle 内部路径，找不到就直接放弃，不做外部兜底搜索。
        let bundleURL = Bundle.main.bundleURL
        let helperURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("MyWallpaperXWallpaperDaemon")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return nil
        }
        return helperURL
    }

    private func attachReaders(for session: DisplayDaemonSession) {
        // daemon 使用按行 JSON 协议，所有输出统一回到主线程解析和状态回写。
        session.inputPipe.fileHandleForWriting.readabilityHandler = nil
        session.outputPipe.fileHandleForReading.readabilityHandler = { [weak self, weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let session else { return }
            DispatchQueue.main.async {
                self.consumeDaemonEvents(from: data, for: session)
            }
        }
        session.errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
        }
    }

    private func cleanupSessionIO(_ session: DisplayDaemonSession) {
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        session.errorPipe.fileHandleForReading.readabilityHandler = nil
        try? session.inputPipe.fileHandleForWriting.close()
        try? session.outputPipe.fileHandleForReading.close()
        try? session.errorPipe.fileHandleForReading.close()
    }

    private func terminateSession(for displayID: CGDirectDisplayID) {
        guard let session = displaySessions.removeValue(forKey: displayID) else { return }

        if session.process.isRunning {
            send(DaemonCommand(action: "stop", videoPath: nil, framePath: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, requestID: nil), to: session)
            session.process.terminate()
        }
        cleanupSessionIO(session)
    }

    private func sendPlayCommand(
        for videoPath: String,
        framePath: String?,
        fillMode: String,
        shouldLoopCurrentItem: Bool,
        to session: DisplayDaemonSession
    ) {
        session.nextRequestID += 1
        let requestID = session.nextRequestID
        session.latestRequestedPlayRequestID = requestID
        send(
            DaemonCommand(
                action: "play",
                videoPath: videoPath,
                framePath: framePath,
                fillMode: fillMode,
                shouldLoopCurrentItem: shouldLoopCurrentItem,
                volume: currentVolumeNormalized,
                playbackRate: targetPlaybackRate,
                requestID: requestID
            ),
            to: session
        )
    }

    func send(_ command: DaemonCommand, to session: DisplayDaemonSession) {
        guard session.process.isRunning else { return }

        do {
            let data = try JSONEncoder().encode(command) + Data([0x0A])
            try session.inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
        }
    }

    private func consumeDaemonEvents(from data: Data, for session: DisplayDaemonSession) {
        // 事件流按换行切分，保证同一条 daemon 输出不会被部分读取打乱协议解析。
        session.outputBuffer.append(data)

        while let newlineIndex = session.outputBuffer.firstIndex(of: 0x0A) {
            let line = session.outputBuffer.prefix(upTo: newlineIndex)
            session.outputBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }
            do {
                let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(line))
                handleDaemonEvent(event, for: session)
            } catch {
            }
        }
    }

    private func handleDaemonEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        // 只处理与当前播放链路相关的事件，忽略无关 daemon 心跳。
        switch event.type {
        case "launched":
            session.launched = true
        case "accepted":
            session.latestAcceptedPlayRequestID = event.requestID
        case "ready":
            session.latestReadyPlayRequestID = event.requestID
            if event.videoPath == currentWallpaper?.path {
                lastFailureVideoPath = nil
                lastFailureAt = 0
                // 成功播放，退避计数归零。
                displayCrashCounts[session.displayID] = 0
            }
        case "failed":
            handlePlaybackFailureEvent(event, for: session)
        case "ended":
            handlePlaybackEndedEvent(event, for: session)
        case "stopped":
            break
        default:
            break
        }
    }

    private func handlePlaybackFailureEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        guard let failedPath = event.videoPath,
              failedPath == currentWallpaper?.path,
              event.requestID == nil || event.requestID == session.latestRequestedPlayRequestID else {
            return
        }

        // 同一路径短时间内只报一次失败，避免大文件或损坏文件触发通知风暴。
        let now = CACurrentMediaTime()
        if lastFailureVideoPath == failedPath && now - lastFailureAt < 1.0 {
            return
        }

        lastFailureVideoPath = failedPath
        lastFailureAt = now

        NotificationCenter.default.post(
            name: Self.playbackFailedNotification,
            object: self,
            userInfo: [
                "videoPath": failedPath,
                "message": event.message ?? "unknown"
            ]
        )
    }

    private func handlePlaybackEndedEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        guard let endedPath = event.videoPath,
              endedPath == currentWallpaper?.path,
              event.requestID == nil || event.requestID == session.latestRequestedPlayRequestID else {
            return
        }

        // 结束事件同样去重，防止自动切换和 daemon 回调双重触发。
        let now = CACurrentMediaTime()
        if lastEndedVideoPath == endedPath && now - lastEndedAt < 1.0 {
            return
        }

        lastEndedVideoPath = endedPath
        lastEndedAt = now

        NotificationCenter.default.post(
            name: Self.playbackEndedNotification,
            object: self,
            userInfo: [
                "videoPath": endedPath
            ]
        )
    }

    func shouldMaintainSession(for displayID: CGDirectDisplayID) -> Bool {
        // 只要显示器仍存在，且当前是多屏模式，就保留 session；否则让它自然退出。
        scanDisplays()
        guard displayIDs.contains(displayID) else { return false }
        if currentMultiDisplayEnabled {
            return true
        }
        return displayID == displayIDs.first
    }

    func scanDisplays() {
        // display 列表只做快照，不做额外缓存，保证和系统当前屏幕拓扑一致。
        displayIDs = NSScreen.screens.compactMap {
            guard let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CGDirectDisplayID(screenNumber.uint32Value)
        }
    }

}
