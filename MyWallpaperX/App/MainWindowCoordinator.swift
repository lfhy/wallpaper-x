//
//  MainWindowCoordinator.swift
//  MyWallpaperX
//

import AppKit

// 集中管理主窗口、Dock 图标和前台激活策略，避免窗口生命周期逻辑散落到多个入口。
enum MainWindowCoordinator {
    private static var mainWindowController: MainWindowController?
    private static var wallpaperManager: WallpaperManager = .shared

    // MARK: - 当前激活模块

    /// 当前激活的模块，由 MainWindowController 通过通知更新。
    /// MyWallpaperApp 的菜单命令通过此属性决定路由目标和启用状态。
    private(set) static var activeModule: MainWindowController.ActiveModule = .videoLibrary

    static func setActiveModule(_ module: MainWindowController.ActiveModule) {
        activeModule = module
    }

    /// 模块退出时，如果当前激活的正是该模块，则回退到视频库。
    static func clearActiveModuleIfMatches(_ module: MainWindowController.ActiveModule) {
        if activeModule == module {
            activeModule = .videoLibrary
        }
    }

    // MARK: - 菜单命令分发

    /// 当前模块是否为视频库（视频库专属菜单项的启用判断）
    static var isVideoLibraryActive: Bool { activeModule == .videoLibrary }

 /// 视频库专属命令（设为壁纸 / 上下切换 / 收藏）是否可用
 static var canUseVideoLibraryOnlyCommands: Bool { isVideoLibraryActive }

 /// 「进入/退出多选」菜单项是否可用
 static var canToggleMultiSelect: Bool {
 switch activeModule {
 case .videoLibrary, .staticImageLibrary:
 return true
 case .onlineLibrary:
 return OnlineDownloadsBridge.shared.isActive
 }
 }

 /// 「全选」菜单项是否可用
 static var canSelectAll: Bool {
 switch activeModule {
 case .videoLibrary, .staticImageLibrary:
 return true
 case .onlineLibrary:
 return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.isMultiSelectMode
 }
 }

    /// 「设为壁纸」- 仅视频库
    static func menuSetAsWallpaper() {
        guard isVideoLibraryActive else { return }
        let manager = WallpaperManager.shared
        if let id = manager.selectedWallpaperId,
           let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
            manager.markCardInteraction()
            manager.requestSetAsWallpaper(wallpaper)
        }
    }

    /// 「切换上一张/下一张」- 仅视频库
    static func menuNavigate(_ direction: ManualNavigationDirection) {
        guard isVideoLibraryActive else { return }
        WallpaperManager.shared.navigateWallpaperManually(direction, userInitiated: true)
    }

    /// 「收藏 / 取消收藏」- 仅视频库
    static func menuToggleFavorite() {
        guard isVideoLibraryActive else { return }
        let manager = WallpaperManager.shared
        UIActionHelper.toggleFavoriteSelection(
            manager: manager,
            selection: manager.currentSelectionContext
        )
    }

    /// 「导入」- Cmd+O，根据当前模块决定导入视频还是图片
    static func menuImport() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            manager.importVideos(
                presentingIn: appModalHostWindow(),
                context: manager.currentImportContext
            )
        case .staticImageLibrary:
            SILService.shared.importFromPanel(presentingIn: appModalHostWindow())
        case .onlineLibrary:
            break  // 在线库无本地导入
        }
    }

    /// 「新建标签」- Cmd+N，根据当前模块决定新建视频标签还是图片标签
    static func menuCreateTag() {
        switch activeModule {
        case .videoLibrary:
            UIActionHelper.presentCreateTag(
                manager: WallpaperManager.shared,
                window: appModalHostWindow()
            )
        case .staticImageLibrary:
            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            let alert = makeAppAlert(
                title: "新建图片标签",
                message: "请输入图片标签名称",
                buttons: ["确定", "取消"],
                accessoryView: inputField
            )
            presentAppAlert(alert, in: appModalHostWindow()) { r in
                guard r == .alertFirstButtonReturn else { return }
                SILService.shared.createSILTag(inputField.stringValue)
            }
        case .onlineLibrary:
            break  // 在线库无标签系统
        }
    }

    /// 「添加标签」- 视频库专属；图片库预留接口（后续实现侧边栏专属标签系统）
    static func menuAddTag() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            UIActionHelper.presentTagPicker(
                manager: manager,
                window: appModalHostWindow()
            ) {}
        case .staticImageLibrary:
            // 图片库标签系统已实现，触发工具栏标签按钮动作
            let svc = SILService.shared
            let ids = svc.silSelectedIDs
            guard !ids.isEmpty else { return }
            let tags = svc.silTags
            guard !tags.isEmpty else {
                let alert = makeAppAlert(title: "无可用标签", message: "请先在侧边栏右键新建图片标签。", buttons: ["好"])
                presentAppAlert(alert, in: appModalHostWindow())
                return
            }
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            picker.addItems(withTitles: tags)
            picker.selectItem(at: 0)
            let alert = makeAppAlert(
                title: "添加图片标签",
                message: "请选择要添加的标签",
                buttons: ["确定", "取消"],
                accessoryView: picker
            )
            presentAppAlert(alert, in: appModalHostWindow()) { r in
                guard r == .alertFirstButtonReturn,
                      let tag = picker.titleOfSelectedItem, !tag.isEmpty else { return }
                // addSILTag 内部已调用 clearSelectionState()，多选会自动退出
                SILService.shared.addSILTag(tag, toSelected: ids)
            }
        case .onlineLibrary:
            break
        }
    }

    /// 「添加标签」菜单项是否可用
    static var canAddTag: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasSingleWallpaperSelection || WallpaperManager.shared.hasAnyWallpaperSelection
        case .staticImageLibrary:
            // 图片库标签系统已实现：有选中且有标签时可用
            return SILService.shared.hasAnySelection && !SILService.shared.silTags.isEmpty
        case .onlineLibrary:
            return false
        }
    }

    /// 「查看信息」- 视频库和图片库各自实现
    static func menuShowInfo() {
        switch activeModule {
        case .videoLibrary:
            UIActionHelper.presentInfo(
                manager: WallpaperManager.shared,
                window: appModalHostWindow()
            )
        case .staticImageLibrary:
            let svc = SILService.shared
            guard let id = svc.selectedID,
                  let w = svc.wallpapers.first(where: { $0.id == id }) else { return }
            svc.detailInfoText(for: w) { text in
                let alert = makeAppAlert(title: "图片信息", message: text, buttons: ["好"])
                presentAppAlert(alert, in: appModalHostWindow())
            }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.showInfo()
            }
        }
    }

    /// 「查看信息」菜单项是否可用
    static var canShowInfo: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasSingleWallpaperSelection
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasSingleSelection
        }
    }

    /// 「进入/退出多选」- 视频库和图片库各自实现
    static func menuToggleMultiSelect() {
        switch activeModule {
        case .videoLibrary:
            WallpaperManager.shared.toggleMultiSelectMode()
        case .staticImageLibrary:
            let svc = SILService.shared
            if svc.isMultiSelectMode { svc.exitMultiSelectMode() } else { svc.enterMultiSelectMode() }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.toggleMultiSelect()
            }
        }
    }

    /// 「全选」- 多选模式下各模块实现
    static func menuSelectAll() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            guard manager.isMultiSelectMode else { return }
            let selection = manager.currentSelectionContext
            let targetIDs = Set(selection.sourceWallpapers(from: manager).map(\.id))
            manager.replaceMultiSelection(with: targetIDs)
        case .staticImageLibrary:
            let svc = SILService.shared
            // 未进入多选模式时自动先进入再全选
            if !svc.isMultiSelectMode { svc.enterMultiSelectMode() }
            svc.selectAll()
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.selectAll()
            }
        }
    }

    /// 「删除选中」- 视频库和图片库各自实现
    static func menuDeleteSelected() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            let selection = manager.currentSelectionContext
            UIActionHelper.performDeleteWithoutConfirmation(
                manager: manager,
                selection: selection,
                window: appModalHostWindow()
            )
        case .staticImageLibrary:
            let svc = SILService.shared
            let ids = svc.silSelectedIDs
            guard !ids.isEmpty else { return }
            if let tag = svc.currentContextTag {
                SILService.shared.removeFromSILTag(tag, ids: ids)
            } else {
                SILService.shared.remove(ids: ids)
            }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.deleteSelected()
            }
        }
    }

    static var canDeleteSelected: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasAnyWallpaperSelection
        case .staticImageLibrary:
            return SILService.shared.hasAnySelection
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasAnySelection
        }
    }

    /// 「搜索」- 各模块聚焦搜索框
    static func menuFocusSearch() {
        mainWindowController?.toolbarController.focusSearch()
    }

    /// 「查看文件」- 视频库和图片库各自实现
    static func menuRevealInFinder() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            if let id = manager.selectedWallpaperId,
               let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
            }
        case .staticImageLibrary:
            let svc = SILService.shared
            if let id = svc.selectedID,
               let wallpaper = svc.wallpapers.first(where: { $0.id == id }) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
            }
        case .onlineLibrary:
            // 区分子页面：已下载项对齐视频库行为（在访达中显示），浏览页执行在线刷新
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.revealInFinder()
            } else {
                OnlineLibraryService.shared.refresh()
            }
        }
    }

    /// 「查看文件」菜单项是否可用
    static var canRevealInFinder: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.selectedWallpaperId != nil
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                return OnlineDownloadsBridge.shared.hasAnySelection
            }
            return true
        }
    }

    /// 「预览」菜单项是否可用
    static var canPreview: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.selectedWallpaperId != nil
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasAnySelection
        }
    }

    static func setDockIconVisible(_ visible: Bool) {
        // Dock 图标显示状态必须和主窗口显隐同步，否则会出现“窗口关了但进程看起来还在前台”的错觉。
        let targetPolicy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }

    /// 菜单命令：预览选中项（QuickLook）
    static func menuPreview() {
        let module = activeModule
        if module == .videoLibrary {
            _ = QuickLookPreviewController.shared.openPreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
        } else if module == .staticImageLibrary {
            _ = SILKeyboardHandler.shared.handleSpace()
        } else if module == .onlineLibrary && OnlineDownloadsBridge.shared.isActive {
            OnlineDownloadsBridge.shared.previewSelected()
        }
    }

    static func configure(with wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        observeOnlineVideoReadyToPlay()
    }

    /// 监听在线库下载完成通知，中转给视频库执行静默导入并播放。
    /// 在线库模块自身不依赖 WallpaperManager，通过此中转保持模块间零耦合。
    private static func observeOnlineVideoReadyToPlay() {
        NotificationCenter.default.addObserver(
            forName: .onlineVideoReadyToPlay,
            object: nil,
            queue: .main
        ) { notification in
            guard let localURL = notification.userInfo?["localURL"] as? URL else { return }
            wallpaperManager.processImportedVideos(
                from: [localURL],
                presentingIn: nil,
                context: .onlinePlayback
            )
        }
    }

    static func mainWindow() -> NSWindow? {
        if let window = mainWindowController?.window {
            return window
        }
        return NSApp.windows.first { window in
            window.identifier?.rawValue == "MainWindow"
        }
    }

    static func activateMainWindow(select category: Category? = nil) {
        if let category {
            wallpaperManager.selectCategory(category)
        }

        // 优先复用现有 controller / window，避免重复创建导致状态丢失。
        if let controller = mainWindowController {
            controller.showWindow(nil)
            return
        }

        if let existingWindow = mainWindow() {
            activate(window: existingWindow)
            return
        }

        let controller = makeMainWindowController()
        controller.showWindow(nil)
    }

    static func activate(window: NSWindow) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                activate(window: window)
            }
            return
        }

        // 激活顺序固定：先恢复 Dock / App 激活态，再把窗口拉到最前并刷新播放状态。
        setDockIconVisible(true)
        window.level = .normal
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFront(nil)
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WallpaperEngine.shared.refreshPlaybackState()
        }
    }

    static func handleWindowWillClose(_ controller: MainWindowController) {
        if mainWindowController === controller {
            mainWindowController = nil
        }
        // 关闭主窗口时隐藏 Dock 图标，维持“窗口即应用入口”的表现。
        setDockIconVisible(false)
    }

    private static func makeMainWindowController() -> MainWindowController {
        let controller = MainWindowController(wallpaperManager: wallpaperManager)
        mainWindowController = controller
        return controller
    }

    static func performZoom(delta: Int) {
        mainWindowController?.performZoom(delta: delta)
    }
}
