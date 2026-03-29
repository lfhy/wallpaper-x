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
        button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Wallpaper Control")
        statusItem?.menu = menu
        rebuildMenu()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 菜单内容每次打开都重新计算，保证图标标题与当前播放 / 静音状态一致。
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        // 菜单动作尽量直接复用主窗口同一套入口，不另造一套状态机。
        menu.removeAllItems()
        
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
