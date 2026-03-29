//
//  MyWallpaperApp.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import SwiftUI

@main
struct MyWallpaperApp: App {
    @StateObject private var wallpaperManager = WallpaperManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // MARK: - 文件菜单
            Group {
                CommandGroup(replacing: .newItem) {
                    Button("打开主界面") {
                        MainWindowCoordinator.activateMainWindow()
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Divider()

                    Button("导入视频") {
                        let manager = WallpaperManager.shared
                        manager.importVideos(
                            presentingIn: appModalHostWindow(),
                            context: manager.currentImportContext
                        )
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
                CommandGroup(replacing: .saveItem) {}
                CommandGroup(replacing: .importExport) {}
                CommandGroup(replacing: .printItem) {}
            }

            // MARK: - 编辑菜单
            Group {
                CommandGroup(replacing: .undoRedo) {}
                CommandGroup(replacing: .textFormatting) {}

                CommandGroup(after: .undoRedo) {
                    Button("全选") {
                        let manager = WallpaperManager.shared
                        guard manager.isMultiSelectMode else { return }
                        let selection = manager.currentSelectionContext
                        let targetIDs = Set(selection.sourceWallpapers(from: manager).map(\.id))
                        manager.replaceMultiSelection(with: targetIDs)
                    }

                    Button("进入 / 退出多选") {
                        WallpaperManager.shared.toggleMultiSelectMode()
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    Divider()

                    Button("删除选中") {
                        let manager = WallpaperManager.shared
                        let selection = manager.currentSelectionContext
                        UIActionHelper.performDeleteWithoutConfirmation(
                            manager: manager,
                            selection: selection,
                            window: appModalHostWindow()
                        )
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }

            // MARK: - 显示菜单
            Group {
                CommandGroup(replacing: .toolbar) {
                    Button("放大缩略图") {
                        let m = WallpaperManager.shared
                        m.gridZoomOffset = max(-2, min(2, m.gridZoomOffset + 1))
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("缩小缩略图") {
                        let m = WallpaperManager.shared
                        m.gridZoomOffset = max(-2, min(2, m.gridZoomOffset - 1))
                    }
                    .keyboardShortcut("+", modifiers: .command)
                }
                CommandGroup(replacing: .sidebar) {}
            }

            // MARK: - 壁纸菜单
            CommandMenu("壁纸") {
                Button("设为当前壁纸") {
                    let manager = WallpaperManager.shared
                    if let id = manager.selectedWallpaperId,
                       let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                        manager.markCardInteraction()
                        manager.requestSetAsWallpaper(wallpaper)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Divider()

                Button("切换下一张") {
                    WallpaperManager.shared.navigateWallpaperManually(.next, userInitiated: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("切换上一张") {
                    WallpaperManager.shared.navigateWallpaperManually(.previous, userInitiated: true)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("收藏 / 取消收藏") {
                    let manager = WallpaperManager.shared
                    UIActionHelper.toggleFavoriteSelection(
                        manager: manager,
                        selection: manager.currentSelectionContext
                    )
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("添加标签") {
                    let manager = WallpaperManager.shared
                    UIActionHelper.presentTagPicker(
                        manager: manager,
                        window: appModalHostWindow()
                    ) {}
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("查看信息") {
                    UIActionHelper.presentInfo(
                        manager: WallpaperManager.shared,
                        window: appModalHostWindow()
                    )
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("查看文件") {
                    let manager = WallpaperManager.shared
                    if let id = manager.selectedWallpaperId,
                       let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // MARK: - 窗口 / 设置 / 帮助
            Group {
                CommandGroup(after: .windowArrangement) {
                    Button("关闭窗口") {
                        NSApp.keyWindow?.performClose(nil)
                    }
                    .keyboardShortcut("w", modifiers: .command)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("偏好设置") {
                        MainWindowCoordinator.activateMainWindow(select: .settings)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    Button("MyWallpaperX 帮助") {
                        NSApplication.shared.showHelp(nil)
                    }
                    .keyboardShortcut("?", modifiers: .command)
                }
            }
        }
    }
}
