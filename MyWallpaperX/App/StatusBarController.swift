//
//  StatusBarController.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var didSetupStatusBar = false
    private let wallpaperManager: WallpaperManager = .shared

    // 状态栏动态刷新定时器（每 2 秒更新一次图标上的 CPU%）
    private var iconRefreshTimer: DispatchSourceTimer?

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.showsStateColumn = true
        return menu
    }()
    
    override init() {
        super.init()
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        guard !didSetupStatusBar else { return }
        didSetupStatusBar = true
        // 状态栏图标只初始化一次，避免重复创建导致菜单 / target 丢失。
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        // 首次用默认图标，定时器起来后会换成动态 CPU% 图标
        button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Wallpaper Control")
        statusItem?.menu = menu
        rebuildMenu()
        startIconRefreshTimer()
    }

    // MARK: - 状态栏图标动态刷新

    private func startIconRefreshTimer() {
        // 首次采样（建立基线，第一次 CPU 差值为 0 属正常）
        SystemMonitor.shared.refresh()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            SystemMonitor.shared.refresh()
            self.updateStatusBarIcon()
        }
        iconRefreshTimer = timer
        timer.resume()
    }

    /// 将 CPU% 渲染到状态栏图标（等宽数字，16pt）
    private func updateStatusBarIcon() {
        let pct = Int((SystemMonitor.shared.stats.cpuUsage * 100).rounded())
        let label = String(format: "%d%%", pct)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let imgSize = NSSize(width: max(size.width + 2, 28), height: 18)

        let img = NSImage(size: imgSize, flipped: false) { rect in
            let y = (rect.height - size.height) / 2
            (label as NSString).draw(
                at: NSPoint(x: (rect.width - size.width) / 2, y: y),
                withAttributes: attrs
            )
            return true
        }
        img.isTemplate = true
        statusItem?.button?.image = img
        statusItem?.button?.imagePosition = .imageOnly
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 菜单内容每次打开都重新计算，保证图标标题与当前播放 / 静音状态一致。
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        // 菜单动作尽量直接复用主窗口同一套入口，不另造一套状态机。
        menu.removeAllItems()

        // ── 系统状态监控区 ──────────────────────────────────────
        // menuNeedsUpdate 每次打开菜单都触发，刷新一次数据即可
        SystemMonitor.shared.refresh()
        let s = SystemMonitor.shared.stats

        // 第一行：CPU + 内存
        var line1 = "CPU \(s.cpuUsageString)   内存 \(s.memUsedString) / \(s.memTotalString)"
        if let t = s.cpuTempString { line1 += "   \(t)" }
        menu.addItem(makeInfoItem(title: line1, systemImageName: "cpu"))

        // 第二行：GPU（有数据才显示）
        var gpuParts: [String] = []
        let gpuStr = s.gpuUsageString
        if gpuStr != "–" { gpuParts.append("GPU \(gpuStr)") }
        if let t = s.gpuTempString { gpuParts.append(t) }
        if !gpuParts.isEmpty {
            menu.addItem(makeInfoItem(title: gpuParts.joined(separator: "   "), systemImageName: "memorychip"))
        }

        // 第三行：网络
        let netLine = "↑ \(s.netUpString)   ↓ \(s.netDownString)"
        menu.addItem(makeInfoItem(title: netLine, systemImageName: "network"))

        menu.addItem(.separator())
        // ── 系统状态监控区结束 ──────────────────────────────────

        menu.addItem(makeItem(title: "打开主界面", systemImageName: "macwindow", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(makeItem(title: "导入视频", systemImageName: "plus.circle", action: #selector(importVideos), keyEquivalent: ""))
        
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "切换壁纸", systemImageName: "arrow.right.circle", action: #selector(switchWallpaper), keyEquivalent: ""))
        
        let playbackTitle = WallpaperEngine.shared.isPlaying() ? "暂停播放" : "继续播放"
        let playbackIcon = WallpaperEngine.shared.isPlaying() ? "pause.circle" : "play.circle"
        menu.addItem(makeItem(title: playbackTitle, systemImageName: playbackIcon, action: #selector(togglePlayback), keyEquivalent: ""))
        
        let muteTitle = wallpaperManager.isMuted ? "关闭静音" : "开启静音"
        let muteIcon = wallpaperManager.isMuted ? "volume.2" : "volume.slash"
        menu.addItem(makeItem(title: muteTitle, systemImageName: muteIcon, action: #selector(toggleMute), keyEquivalent: ""))
        
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "偏好设置", systemImageName: "gearshape", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        
        let quitItem = makeItem(title: "退出", systemImageName: "xmark.circle", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    /// 纯展示行：无动作、灰色文字、带小图标
    private func makeInfoItem(title: String, systemImageName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 13, height: 13)
            item.image = image
        }
        return item
    }

    private func makeItem(title: String, systemImageName: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
        }
        return item
    }
    
    @objc private func openMainWindow() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async {
            MainWindowCoordinator.activateMainWindow()
        }
    }
    
    @objc private func importVideos() {
        wallpaperManager.importVideos(
            presentingIn: appModalHostWindow(),
            context: wallpaperManager.currentImportContext
        )
    }
    
    @objc private func switchWallpaper() {
        guard !wallpaperManager.wallpapers.isEmpty else { return }
        wallpaperManager.navigateWallpaperManually(.next, userInitiated: true)
    }
    
    @objc private func togglePlayback() {
        // 状态栏播放按钮只做一键切换，状态最终还是以 engine 为准。
        WallpaperEngine.shared.togglePlayback()
        wallpaperManager.isPlaying = WallpaperEngine.shared.isPlaying()
    }
    
    @objc private func toggleMute() {
        wallpaperManager.setMuted(!wallpaperManager.isMuted)
    }
    
    @objc private func openSettings() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async {
            MainWindowCoordinator.activateMainWindow(select: .settings)
        }
    }
    
    @objc private func quitApp() {
        let alert = makeAppAlert(
            title: "确定要退出吗？",
            message: "壁纸将停止播放。",
            buttons: ["退出", "取消"]
        )

        presentAppAlert(alert, in: appModalHostWindow()) { response in
            guard response == .alertFirstButtonReturn else { return }
            NSApp.terminate(nil)
        }
    }
}
