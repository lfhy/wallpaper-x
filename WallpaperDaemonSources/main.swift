import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

// DaemonCommand / DaemonEvent 定义在 DaemonProtocol.swift，
// 通过 Xcode Target Membership 共享到此 target，此处不再重复定义。

private func daemonLog(_ message: String) {
    fputs("daemon: \(message)\n", stderr)
}

private final class WallpaperDaemon {
    private enum Slot {
        case primary
        case secondary
    }

    private let displayID: CGDirectDisplayID
    private let window: NSWindow
    private let fallbackLayer: CALayer
    private let primaryPlayer: AVQueuePlayer
    private let secondaryPlayer: AVQueuePlayer
    private let primaryLayer: AVPlayerLayer
    private let secondaryLayer: AVPlayerLayer

    private var primaryLooper: AVPlayerLooper?
    private var secondaryLooper: AVPlayerLooper?
    private var pendingStatusObservation: NSKeyValueObservation?
    private var pendingEndObservation: NSObjectProtocol?
    private var loopEndObservation: NSObjectProtocol?  // setLoop 动态开启循环时的手动 seek 观察者
    private var pendingDisplayObservation: NSKeyValueObservation?
    private var pendingDisplayFallbackWorkItem: DispatchWorkItem?
    private var currentVideoPath: String?
    private var currentRequestID: Int?
    private var activeSlot: Slot = .primary
    private var switchToken: Int = 0
    private var currentVolume: Float = 0.5
    private var playbackRate: Float = 1.0
    private var paused = false
    private var currentFillMode: String = "填充屏幕"
    private let crossfadeDuration: TimeInterval = 0.25

    init?(displayID: CGDirectDisplayID) {
        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen not found for display \(displayID)")
            return nil
        }

        self.displayID = displayID
        self.primaryPlayer = WallpaperDaemon.makeQueuePlayer()
        self.secondaryPlayer = WallpaperDaemon.makeQueuePlayer()

        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = WallpaperDaemon.desktopWindowLevel
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor

        self.fallbackLayer = CALayer()
        self.primaryLayer = AVPlayerLayer(player: primaryPlayer)
        self.secondaryLayer = AVPlayerLayer(player: secondaryPlayer)
        fallbackLayer.frame = window.contentView?.bounds ?? CGRect(origin: .zero, size: screen.frame.size)
        fallbackLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        fallbackLayer.opacity = 0
        fallbackLayer.contentsGravity = .resizeAspectFill
        window.contentView?.layer?.addSublayer(fallbackLayer)
        for layer in [primaryLayer, secondaryLayer] {
            layer.frame = window.contentView?.bounds ?? CGRect(origin: .zero, size: screen.frame.size)
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 0
            window.contentView?.layer?.addSublayer(layer)
        }

        window.orderFrontRegardless()
        emit(type: "launched", requestID: nil, message: nil, videoPath: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func handle(_ command: DaemonCommand) {
        switch command.action {
        case "play":
            guard let videoPath = command.videoPath else { return }
            emit(type: "accepted", requestID: command.requestID, message: nil, videoPath: videoPath)
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
            }
            if let volume = command.volume {
                currentVolume = min(max(volume, 0), 1)
            }
            play(
                videoPath: videoPath,
                framePath: command.framePath,
                fillMode: command.fillMode ?? "aspectFill",
                shouldLoopCurrentItem: command.shouldLoopCurrentItem ?? false,
                requestID: command.requestID
            )
        case "pause":
            paused = true
            for player in players {
                player.pause()
            }
        case "resume":
            paused = false
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
            }
            // 用 rate 属性而不是 playImmediately，避免重置 AVPlayerLooper 导致视频从头播放。
            activePlayer.rate = playbackRate
        case "setVolume":
            if let volume = command.volume {
                currentVolume = min(max(volume, 0), 1)
                for player in players {
                    player.volume = currentVolume
                }
            }
        case "setFillMode":
            if let fillMode = command.fillMode, fillMode != currentFillMode {
                currentFillMode = fillMode
                animateLayerFrameForFillMode(fillMode)
                // fallback layer 也同步更新 gravity（静帧显示时）。
                let fallbackGravity: CALayerContentsGravity = fillMode == "aspectFit" ? .resizeAspect : .resizeAspectFill
                fallbackLayer.contentsGravity = fallbackGravity
            }
        case "setLoop":
            // 动态切换循环状态，不重建 looper，不重载视频，完全无感。
            if let shouldLoop = command.shouldLoopCurrentItem {
                if shouldLoop {
                    // 开启循环：监听播放结束事件，seek 到开头重新播放，不重建任何播放器结构。
                    if loopEndObservation == nil, let item = activePlayer.currentItem {
                        loopEndObservation = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: item,
                            queue: .main
                        ) { [weak self] _ in
                            guard let self else { return }
                            self.activePlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                            self.activePlayer.rate = self.playbackRate
                        }
                        // 移除 playbackEnded 观察者，避免循环结束时误触发切换。
                        if let obs = pendingEndObservation {
                            NotificationCenter.default.removeObserver(obs)
                            pendingEndObservation = nil
                        }
                    } else {
                    }
                } else {
                    // 关闭循环：移除 loopEndObservation，重新注册 playbackEnded 观察者。
                    // 不清理 looper，清理 looper 会导致 AVQueuePlayer 队列变空黑屏。
                    // looper 管理的 item 同样会触发 didPlayToEndTime，直接监听即可。
                    if let obs = loopEndObservation {
                        NotificationCenter.default.removeObserver(obs)
                        loopEndObservation = nil
                    }
                    if pendingEndObservation == nil,
                       let item = activePlayer.currentItem,
                       let videoPath = currentVideoPath {
                        observePlaybackEnd(for: item, requestID: currentRequestID, videoPath: videoPath)
                    }
                    // .pause：视频播完停在最后一帧并触发 didPlayToEndTime，让主进程收到 ended 事件切下一张。
                    activePlayer.actionAtItemEnd = .pause
                }
            }
        case "stop":
            daemonLog("received stop")
            shutdown()
        default:
            break
        }
    }

    func shutdown() {
        pendingStatusObservation = nil
        pendingEndObservation = nil
        pendingDisplayObservation = nil
        loopEndObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
        for player in players {
            player.pause()
            player.removeAllItems()
        }
        primaryLooper = nil
        secondaryLooper = nil
        window.orderOut(nil)
        fallbackLayer.contents = nil
        emit(type: "stopped", requestID: nil, message: nil, videoPath: nil)
        daemonLog("shutdown")
        NSApp.terminate(nil)
    }

    private var players: [AVQueuePlayer] {
        [primaryPlayer, secondaryPlayer]
    }

    private var activePlayer: AVQueuePlayer {
        activeSlot == .primary ? primaryPlayer : secondaryPlayer
    }

    private var inactivePlayer: AVQueuePlayer {
        activeSlot == .primary ? secondaryPlayer : primaryPlayer
    }

    private var activeLayer: AVPlayerLayer {
        activeSlot == .primary ? primaryLayer : secondaryLayer
    }

    private var inactiveLayer: AVPlayerLayer {
        activeSlot == .primary ? secondaryLayer : primaryLayer
    }

    private func setInactiveLooper(_ looper: AVPlayerLooper?) {
        switch activeSlot {
        case .primary:
            secondaryLooper = looper
        case .secondary:
            primaryLooper = looper
        }
    }

    private func clearActiveLooper() {
        switch activeSlot {
        case .primary:
            primaryLooper = nil
        case .secondary:
            secondaryLooper = nil
        }
    }

    private func play(videoPath: String, framePath: String?, fillMode: String, shouldLoopCurrentItem: Bool, requestID: Int?) {
        guard FileManager.default.fileExists(atPath: videoPath) else {
            daemonLog("video not found \(videoPath)")
            emit(type: "failed", requestID: requestID, message: "video_not_found", videoPath: videoPath)
            return
        }

        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen disappeared \(displayID)")
            emit(type: "failed", requestID: requestID, message: "screen_not_found", videoPath: videoPath)
            shutdown()
            return
        }

        switchToken += 1
        let token = switchToken
        pendingStatusObservation = nil

        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        window.level = WallpaperDaemon.desktopWindowLevel
        currentFillMode = fillMode
        updateLayerFrames()

        // 两种模式统一用 resizeAspectFill，通过 layer frame 大小控制显示区域。
        let fallbackGravity: CALayerContentsGravity = .resizeAspectFill
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryLayer.videoGravity = .resizeAspectFill
        secondaryLayer.videoGravity = .resizeAspectFill
        CATransaction.commit()

        showFallback(framePath: framePath, gravity: fallbackGravity, fillMode: fillMode)

        let incomingPlayer = inactivePlayer
        incomingPlayer.pause()
        incomingPlayer.removeAllItems()
        // 非循环模式下停留在最后一帧，避免播完到下一条命令之间出现空白闪烁。
        // 循环模式保持队列推进行为，由 looper 负责无缝衔接。
        incomingPlayer.actionAtItemEnd = shouldLoopCurrentItem ? .advance : .none
        setInactiveLooper(nil)
        if let pendingEndObservation {
            NotificationCenter.default.removeObserver(pendingEndObservation)
            self.pendingEndObservation = nil
        }
        if let loopEndObservation {
            NotificationCenter.default.removeObserver(loopEndObservation)
            self.loopEndObservation = nil
        }

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 1.5
        item.preferredMaximumResolution = CGSize(width: screen.frame.width, height: screen.frame.height)

        incomingPlayer.volume = currentVolume
        if shouldLoopCurrentItem {
            let looper = AVPlayerLooper(player: incomingPlayer, templateItem: item)
            setInactiveLooper(looper)
        } else {
            incomingPlayer.insert(item, after: nil)
            observePlaybackEnd(for: item, requestID: requestID, videoPath: videoPath)
        }
        waitUntilPlayerReady(incomingPlayer, token: token, requestID: requestID, videoPath: videoPath)
    }

    private func animateLayerFrameForFillMode(_ fillMode: String) {
        guard let contentBounds = window.contentView?.bounds else { return }
        let targetFrame = layerFrameForFillMode(fillMode, in: contentBounds)

        let layer = activeLayer
        guard layer.opacity > 0,
              targetFrame.width > 0, targetFrame.height > 0 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for l in [primaryLayer, secondaryLayer] { l.frame = targetFrame }
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
            return
        }

        // 读取动画前的视觉 frame（presentation layer）。
        let fromFrame = layer.presentation()?.frame ?? layer.frame

        guard abs(fromFrame.width - targetFrame.width) > 0.5 ||
              abs(fromFrame.height - targetFrame.height) > 0.5 ||
              abs(fromFrame.midX - targetFrame.midX) > 0.5 ||
              abs(fromFrame.midY - targetFrame.midY) > 0.5 else {
            // 无变化，静默设值。
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for l in [primaryLayer, secondaryLayer] { l.frame = targetFrame }
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
            return
        }

        let duration: CFTimeInterval = 0.42
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

        // inactive layer 直接静默设目标值，不做动画。
        let inactive = inactiveLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inactive.frame = targetFrame
        fallbackLayer.frame = contentBounds
        CATransaction.commit()

        // active layer：先静默设到旧 frame（和当前 presentation 一致），
        // 然后用 CATransaction 的隐式动画把 frame 推到目标值。
        // 这样视频内容始终和 layer frame 对齐，不会出现黑边。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = fromFrame
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        layer.frame = targetFrame
        CATransaction.commit()
    }

    /// 在填充模式改变时，对当前正在显示的 layer 做从「当前视觉尺寸」到「目标视觉尺寸」的平滑缩放动画。
    /// 原理：计算视频在两种 gravity 下的实际渲染 rect，用 transform 动画从旧 rect 缩放到新 rect。
    private func animateFillModeTransitionIfNeeded(to newGravity: AVLayerVideoGravity, bounds: CGRect) {
        let layer = activeLayer
        guard layer.opacity > 0,
              layer.videoGravity != newGravity,
              let videoSize = naturalVideoSize(from: layer),
              videoSize.width > 0, videoSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let fromRect = renderedRect(for: layer.videoGravity, videoSize: videoSize, bounds: bounds)
        let toRect   = renderedRect(for: newGravity,         videoSize: videoSize, bounds: bounds)

        guard fromRect.width > 0, toRect.width > 0 else { return }

        // 动画用 transform 而非改 frame，这样不干扰 autoresizing 和 fill-mode 本身的布局。
        let scaleX = fromRect.width  / toRect.width
        let scaleY = fromRect.height / toRect.height
        let tx = fromRect.midX - toRect.midX
        let ty = fromRect.midY - toRect.midY

        let startTransform = CATransform3DTranslate(CATransform3DMakeScale(scaleX, scaleY, 1), tx / scaleX, ty / scaleY, 0)

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = startTransform
        anim.toValue   = CATransform3DIdentity
        anim.duration  = 0.32
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0) // material-style ease
        anim.fillMode  = .backwards
        anim.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.add(anim, forKey: "fillModeTransition")
    }

    /// 根据 videoGravity 和视频原始尺寸计算视频在 bounds 内的实际渲染 CGRect。
    private func renderedRect(for gravity: AVLayerVideoGravity, videoSize: CGSize, bounds: CGRect) -> CGRect {
        let boundsAspect = bounds.width / bounds.height
        let videoAspect  = videoSize.width / videoSize.height

        switch gravity {
        case .resizeAspect:
            // 适应：最长边对齐 bounds，另一边缩放，居中。
            if videoAspect > boundsAspect {
                let h = bounds.width / videoAspect
                return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            } else {
                let w = bounds.height * videoAspect
                return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
            }
        case .resizeAspectFill:
            // 填充：最短边对齐 bounds，另一边超出裁剪，居中。
            if videoAspect > boundsAspect {
                let w = bounds.height * videoAspect
                return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
            } else {
                let h = bounds.width / videoAspect
                return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            }
        default:
            return bounds
        }
    }

    /// 从当前活跃 AVPlayerLayer 读取视频原始尺寸（需要 player 已有 currentItem）。
    /// 使用 presentationSize 替代废弃的同步 track 属性，macOS 10.7+ 可用，无废弃警告。
    private func naturalVideoSize(from layer: AVPlayerLayer) -> CGSize? {
        guard let item = layer.player?.currentItem else { return nil }
        let size = item.presentationSize
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private func activatePreparedPlayer(requestID: Int?, videoPath: String?) {
        let incomingPlayer = inactivePlayer
        let incomingLayer = inactiveLayer

        // 立即更新 currentVideoPath 和 currentRequestID，不等动画结束。
        // 这样 setLoop false 到达时能正确注册到新视频的 pendingEndObservation。
        if let vp = videoPath {
            currentVideoPath = vp
            currentRequestID = requestID
        }

        incomingPlayer.volume = currentVolume
        if paused {
            incomingPlayer.pause()
        } else {
            // 用 rate 属性而不是 playImmediately，避免重置 AVPlayerLooper 导致视频从头播放。
            incomingPlayer.rate = playbackRate
        }

        // incomingLayer 静默设到目标 frame，opacity = 0 完全隐藏，全程不可见。
        // activeLayer（旧视频）保持原 frame 不动。
        // fallbackLayer 立即隐藏，不等 finishVisualSwitch，避免静帧在切换动画期间透出。
        let targetFrame: CGRect
        if let contentBounds = window.contentView?.bounds {
            targetFrame = layerFrameForFillMode(currentFillMode, in: contentBounds, sourceLayer: incomingLayer)
        } else {
            targetFrame = .zero
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incomingLayer.transform = CATransform3DIdentity
        if targetFrame != .zero { incomingLayer.frame = targetFrame }
        incomingLayer.opacity = 0
        fallbackLayer.opacity = 0  // 视频就绪时立即隐藏静帧，不等动画开始
        CATransaction.commit()

        commitVisualSwitchWhenReady(incomingLayer: incomingLayer, targetFrame: targetFrame, requestID: requestID, videoPath: videoPath)
    }

    private func commitVisualSwitchWhenReady(incomingLayer: AVPlayerLayer, targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()

        let performSwitch = { [weak self] in
            guard let self else { return }
            self.pendingDisplayObservation = nil
            self.pendingDisplayFallbackWorkItem?.cancel()
            self.pendingDisplayFallbackWorkItem = nil
            self.finishVisualSwitch(targetFrame: targetFrame, requestID: requestID, videoPath: videoPath)
        }

        if incomingLayer.isReadyForDisplay {
            performSwitch()
            return
        }

        pendingDisplayObservation = incomingLayer.observe(\.isReadyForDisplay, options: [.new]) { _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { performSwitch() }
        }

        let fallbackWorkItem = DispatchWorkItem(block: performSwitch)
        pendingDisplayFallbackWorkItem = fallbackWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: fallbackWorkItem)
    }

    private func finishVisualSwitch(targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        let incomingLayer = inactiveLayer
        let outgoingLayer = activeLayer
        let isFirstPlay = outgoingLayer.opacity == 0
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

        let previousSlot = activeSlot
        activeSlot = activeSlot == .primary ? .secondary : .primary

        let cleanupOutgoing = { [weak self] in
            guard let self else { return }
            switch previousSlot {
            case .primary:
                self.primaryPlayer.pause()
                self.primaryPlayer.removeAllItems()
            case .secondary:
                self.secondaryPlayer.pause()
                self.secondaryPlayer.removeAllItems()
            }
            self.clearLooper(for: previousSlot)
        }

        // 首次播放无动画，直接显示。
        guard !isFirstPlay else {
            currentVideoPath = videoPath
            currentRequestID = requestID
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 1
            outgoingLayer.opacity = 0
            fallbackLayer.opacity = 0
            CATransaction.commit()
            emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath)
            DispatchQueue.main.asyncAfter(deadline: .now() + crossfadeDuration, execute: cleanupOutgoing)
            return
        }

        // 阶段1开始：立即隐藏 fallbackLayer（静帧占位），避免它在动画期间叠在背后产生重叠。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.opacity = 0
        CATransaction.commit()

        // 判断旧视频是否需要 frame 动画（尺寸或位置有变化）。
        let outFrame = outgoingLayer.presentation()?.frame ?? outgoingLayer.frame
        let needsFrameAnim = targetFrame != .zero
            && (abs(outFrame.width  - targetFrame.width)  > 0.5
                || abs(outFrame.height - targetFrame.height) > 0.5
                || abs(outFrame.midX   - targetFrame.midX)   > 0.5
                || abs(outFrame.midY   - targetFrame.midY)   > 0.5)

        // crossfade 闭包：新视频在目标 frame 淡入，旧视频淡出，不做 frame 动画。
        let doCrossfade = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 0
            outgoingLayer.opacity = 1
            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setAnimationDuration(self.crossfadeDuration)
            CATransaction.setAnimationTimingFunction(timing)
            incomingLayer.opacity = 1
            outgoingLayer.opacity = 0
            CATransaction.commit()

            self.emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.crossfadeDuration, execute: cleanupOutgoing)
        }

        guard needsFrameAnim else {
            // 同尺寸切换：直接 crossfade。
            doCrossfade()
            return
        }

        // 旧视频 transform 缩放淡出，新视频 transform 缩放淡入，同时进行。
        // outgoingLayer 保持在 outFrame 不动，只用 anchorPoint + transform 做缩放淡出。
        // incomingLayer 已在 targetFrame，用 transform 从旧尺寸缩放到目标尺寸淡入。
        let scaleX = targetFrame.width  / outFrame.width
        let scaleY = targetFrame.height / outFrame.height
        let animDuration: CFTimeInterval = 0.55
        let transformTiming = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
        let opacityTiming   = CAMediaTimingFunction(controlPoints: 0.4,  0.0,  0.6, 1.0)

        // 两个 layer 用 position + scale 分离动画，完全解耦位移和缩放。
        // 两者中心点走相同的轨迹（outFrame.mid → targetFrame.mid），
        // 无论垂直居中基线是否一致，视觉上完美对齐，不会过度缩放或漂移。
        //
        // anchorPoint 统一设回 (0.5, 0.5)，position 直接控制中心点。
        // outgoingLayer: position outFrame.mid → targetFrame.mid, scale 1 → (scaleX, scaleY)
        // incomingLayer: position outFrame.mid → targetFrame.mid, scale (1/scaleX, 1/scaleY) → 1
        let outMid    = CGPoint(x: outFrame.midX,    y: outFrame.midY)
        let targetMid = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // outgoingLayer 保持原 frame，anchorPoint 默认中心，position = outFrame.mid。
        outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        outgoingLayer.frame       = outFrame
        outgoingLayer.transform   = CATransform3DIdentity
        outgoingLayer.opacity     = 0   // model 终态
        // incomingLayer 已在 targetFrame，model 终态 position = targetFrame.mid。
        incomingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        incomingLayer.frame       = targetFrame
        incomingLayer.transform   = CATransform3DIdentity
        incomingLayer.opacity     = 1   // model 终态
        CATransaction.commit()

        let now = CACurrentMediaTime()

        // outgoingLayer position: outFrame.mid → targetFrame.mid
        let outPosAnim = CABasicAnimation(keyPath: "position")
        outPosAnim.fromValue       = outMid
        outPosAnim.toValue         = targetMid
        outPosAnim.duration        = animDuration
        outPosAnim.timingFunction  = transformTiming
        outPosAnim.fillMode        = .backwards
        outPosAnim.isRemovedOnCompletion = true
        outPosAnim.beginTime       = now

        // outgoingLayer scale: identity → (scaleX, scaleY)
        let outScaleAnim = CABasicAnimation(keyPath: "transform")
        outScaleAnim.fromValue      = CATransform3DIdentity
        outScaleAnim.toValue        = CATransform3DMakeScale(scaleX, scaleY, 1)
        outScaleAnim.duration       = animDuration
        outScaleAnim.timingFunction = transformTiming
        outScaleAnim.fillMode       = .backwards
        outScaleAnim.isRemovedOnCompletion = true
        outScaleAnim.beginTime      = now

        let outOpacityAnim = CABasicAnimation(keyPath: "opacity")
        outOpacityAnim.fromValue      = 1
        outOpacityAnim.toValue        = 0
        outOpacityAnim.duration       = animDuration
        outOpacityAnim.timingFunction = opacityTiming
        outOpacityAnim.fillMode       = .backwards
        outOpacityAnim.isRemovedOnCompletion = true
        outOpacityAnim.beginTime      = now

        // incomingLayer position: outFrame.mid → targetFrame.mid
        let inPosAnim = CABasicAnimation(keyPath: "position")
        inPosAnim.fromValue       = outMid
        inPosAnim.toValue         = targetMid
        inPosAnim.duration        = animDuration
        inPosAnim.timingFunction  = transformTiming
        inPosAnim.fillMode        = .backwards
        inPosAnim.isRemovedOnCompletion = true
        inPosAnim.beginTime       = now

        // incomingLayer scale: (inStartScaleX, inStartScaleY) → identity
        let inStartScaleX = outFrame.width  / targetFrame.width
        let inStartScaleY = outFrame.height / targetFrame.height
        let inScaleAnim = CABasicAnimation(keyPath: "transform")
        inScaleAnim.fromValue      = CATransform3DMakeScale(inStartScaleX, inStartScaleY, 1)
        inScaleAnim.toValue        = CATransform3DIdentity
        inScaleAnim.duration       = animDuration
        inScaleAnim.timingFunction = transformTiming
        inScaleAnim.fillMode       = .backwards
        inScaleAnim.isRemovedOnCompletion = true
        inScaleAnim.beginTime      = now

        let inOpacityAnim = CABasicAnimation(keyPath: "opacity")
        inOpacityAnim.fromValue      = 0
        inOpacityAnim.toValue        = 1
        inOpacityAnim.duration       = animDuration
        inOpacityAnim.timingFunction = opacityTiming
        inOpacityAnim.fillMode       = .backwards
        inOpacityAnim.isRemovedOnCompletion = true
        inOpacityAnim.beginTime      = now

        outgoingLayer.add(outPosAnim,    forKey: "switchOutPosition")
        outgoingLayer.add(outScaleAnim,  forKey: "switchOutTransform")
        outgoingLayer.add(outOpacityAnim, forKey: "switchOutOpacity")
        incomingLayer.add(inPosAnim,     forKey: "switchInPosition")
        incomingLayer.add(inScaleAnim,   forKey: "switchInTransform")
        incomingLayer.add(inOpacityAnim, forKey: "switchInOpacity")

        currentVideoPath = videoPath
        currentRequestID = requestID
        emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { [weak self] in
            guard self != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.transform   = CATransform3DIdentity
            outgoingLayer.transform   = CATransform3DIdentity
            outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            incomingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            CATransaction.commit()
            cleanupOutgoing()
        }
    }

    private func clearLooper(for slot: Slot) {
        switch slot {
        case .primary:
            primaryLooper = nil
        case .secondary:
            secondaryLooper = nil
        }
    }

    private func observePlaybackEnd(for item: AVPlayerItem, requestID: Int?, videoPath: String) {
        pendingEndObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            daemonLog("playbackEnded fired for \(videoPath)")
            self.pendingEndObservation = nil
            self.emit(type: "ended", requestID: requestID, message: nil, videoPath: videoPath)
        }
    }

    private func updateLayerFrames() {
        guard let contentBounds = window.contentView?.bounds else { return }
        fallbackLayer.frame = contentBounds
        // 只重置 inactive layer（即将播放新视频的 slot），不动 active layer。
        // 修改 active layer 的 frame 会导致正在播放的旧视频瞬间跳变，产生抖动。
        // 同时把 inactiveLayer opacity 锁定为 0，防止在准备期间 CA 渲染出闪帧。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inactiveLayer.frame = contentBounds
        inactiveLayer.opacity = 0
        CATransaction.commit()
    }

    /// 根据填充模式和可见区域计算目标 layer frame。
    /// sourceLayer 不传时默认从 activeLayer 读取视频尺寸；切换视频时传入 incomingLayer 避免读到空旧 layer。
    private func layerFrameForFillMode(_ fillMode: String, in bounds: CGRect, sourceLayer: AVPlayerLayer? = nil) -> CGRect {
        let layerForSize = sourceLayer ?? activeLayer
        guard fillMode == "aspectFit",
              let videoSize = naturalVideoSize(from: layerForSize),
              videoSize.width > 0, videoSize.height > 0 else {
            return bounds
        }
        let boundsAspect = bounds.width / bounds.height
        let videoAspect = videoSize.width / videoSize.height
        let w: CGFloat
        let h: CGFloat
        if videoAspect > boundsAspect {
            w = bounds.width
            h = bounds.width / videoAspect
        } else {
            h = bounds.height
            w = bounds.height * videoAspect
        }
        // 垂直居中基准选择：
        // - 视频高度 ≤ visibleFrame 高度：用 visibleFrame 居中（Dock/状态栏之间），适合 16:9 等标准比例。
        // - 视频高度 > visibleFrame 高度：用整个屏幕（bounds）居中，避免非标准比例视频贴顶或遮 Dock。
        let screen = NSScreen.screens.first { $0.frame.origin == window.frame.origin && $0.frame.size == window.frame.size }
                  ?? NSScreen.screens.first { NSMouseInRect(window.frame.origin, $0.frame, false) }
                  ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? bounds

        let centerY: CGFloat
        if h <= visibleFrame.height {
            let visibleMinY = visibleFrame.minY - window.frame.minY
            let visibleMaxY = visibleFrame.maxY - window.frame.minY
            centerY = (visibleMinY + visibleMaxY) / 2
        } else {
            centerY = bounds.height / 2
        }

        let x = (bounds.width - w) / 2
        let y = centerY - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func showFallback(framePath: String?, gravity: CALayerContentsGravity, fillMode: String? = nil) {
        fallbackLayer.contentsGravity = gravity
        guard let framePath,
              FileManager.default.fileExists(atPath: framePath),
              let image = NSImage(contentsOfFile: framePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fallbackLayer.contents = nil
            fallbackLayer.opacity = 0
            return
        }

        // 保持原尺寸时：用图片尺寸计算等比 frame，让 fallback layer frame 与视频 layer
        // 最终 frame 一致，crossfade 时无尺寸跳变。
        if fillMode == "aspectFit",
           let contentBounds = window.contentView?.bounds {
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            if imageSize.width > 0, imageSize.height > 0 {
                let imageAspect = imageSize.width / imageSize.height
                let boundsAspect = contentBounds.width / contentBounds.height
                let w: CGFloat
                let h: CGFloat
                if imageAspect > boundsAspect {
                    w = contentBounds.width
                    h = contentBounds.width / imageAspect
                } else {
                    h = contentBounds.height
                    w = contentBounds.height * imageAspect
                }
                // 垂直居中于可见区域（排除 Dock 和 menuBar）。
                let screen = NSScreen.screens.first { $0.frame.origin == window.frame.origin && $0.frame.size == window.frame.size }
                          ?? NSScreen.main
                let visibleFrame = screen?.visibleFrame ?? contentBounds
                let visibleMinY = visibleFrame.minY - window.frame.minY
                let visibleMaxY = visibleFrame.maxY - window.frame.minY
                let centerY = (visibleMinY + visibleMaxY) / 2
                let fallbackFrame = CGRect(
                    x: (contentBounds.width - w) / 2,
                    y: centerY - h / 2,
                    width: w,
                    height: h
                )
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                fallbackLayer.frame = fallbackFrame
                fallbackLayer.contents = cgImage
                fallbackLayer.opacity = 1
                CATransaction.commit()
                return
            }
        }

        // 填充屏幕：fallback layer 还原满屏 frame。
        if let contentBounds = window.contentView?.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.contents = cgImage
        fallbackLayer.opacity = 1
        CATransaction.commit()
    }

    private func waitUntilPlayerReady(_ player: AVQueuePlayer, token: Int, requestID: Int?, videoPath: String, attempt: Int = 0) {
        guard switchToken == token else { return }

        guard let currentItem = player.currentItem else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    self?.waitUntilPlayerReady(player, token: token, requestID: requestID, videoPath: videoPath, attempt: attempt + 1)
                }
            } else {
                daemonLog("fallback activate without currentItem token=\(token)")
                activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
            }
            return
        }

        switch currentItem.status {
        case .readyToPlay:
            activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
        case .failed:
            daemonLog("current item failed token=\(token) error=\(currentItem.error?.localizedDescription ?? "unknown")")
            emit(type: "failed", requestID: requestID, message: "item_failed", videoPath: videoPath)
        case .unknown:
            pendingStatusObservation = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                guard self.switchToken == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.pendingStatusObservation = nil
                    DispatchQueue.main.async {
                        guard self.switchToken == token else { return }
                        self.activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
                    }
                case .failed:
                    self.pendingStatusObservation = nil
                    daemonLog("observed item failed token=\(token) error=\(item.error?.localizedDescription ?? "unknown")")
                    self.emit(type: "failed", requestID: requestID, message: "item_failed", videoPath: videoPath)
                default:
                    break
                }
            }
        @unknown default:
            daemonLog("unknown player item status token=\(token)")
            activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
        }
    }

    @objc private func handleScreenParametersChanged() {
        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            return
        }
        window.setFrame(screen.frame, display: true)
        updateLayerFrames()
    }

    private static func makeQueuePlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.isMuted = false
        return player
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            guard let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == displayID
        }
    }

    private static var desktopWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    }

    private func emit(type: String, requestID: Int?, message: String?, videoPath: String?) {
        let event = DaemonEvent(
            type: type,
            displayID: displayID,
            requestID: requestID,
            message: message,
            videoPath: videoPath
        )

        do {
            let data = try JSONEncoder().encode(event) + Data([0x0A])
            FileHandle.standardOutput.write(data)
        } catch {
            daemonLog("failed to emit event \(type): \(error.localizedDescription)")
        }
    }
}

private final class CommandReader {
    private var buffer = Data()
    private let decoder = JSONDecoder()
    private let daemon: WallpaperDaemon

    init(daemon: WallpaperDaemon) {
        self.daemon = daemon
    }

    func start() {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                DispatchQueue.main.async {
                    self.daemon.shutdown()
                }
                return
            }

            self.buffer.append(data)
            self.consumeBuffer()
        }
    }

    private func consumeBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }
            do {
                let command = try decoder.decode(DaemonCommand.self, from: Data(line))
                DispatchQueue.main.async {
                    self.daemon.handle(command)
                }
            } catch {
                daemonLog("failed to decode command \(error.localizedDescription)")
            }
        }
    }
}

private func parseDisplayID() -> CGDirectDisplayID? {
    let args = CommandLine.arguments
    guard let flagIndex = args.firstIndex(of: "--display-id"),
          args.indices.contains(flagIndex + 1),
          let value = UInt32(args[flagIndex + 1]) else {
        return nil
    }
    return CGDirectDisplayID(value)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard let displayID = parseDisplayID() else {
    daemonLog("missing --display-id")
    exit(1)
}

guard let daemon = WallpaperDaemon(displayID: displayID) else {
    exit(2)
}

private let reader = CommandReader(daemon: daemon)
reader.start()
RunLoop.main.run()
