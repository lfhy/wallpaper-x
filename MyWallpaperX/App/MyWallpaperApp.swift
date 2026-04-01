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
                    Button("新建标签") {
                        MainWindowCoordinator.menuCreateTag()
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Divider()

                    Button("导入") {
                        MainWindowCoordinator.menuImport()
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
                        MainWindowCoordinator.menuSelectAll()
                    }

                    Button("进入 / 退出多选") {
                        MainWindowCoordinator.menuToggleMultiSelect()
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    Divider()

                    Button("删除选中") {
                        MainWindowCoordinator.menuDeleteSelected()
                    }
                    .keyboardShortcut(.delete, modifiers: .command)

                    Divider()

                    Button("搜索") {
                        MainWindowCoordinator.menuFocusSearch()
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
            }

            // MARK: - 显示菜单
            Group {
                CommandGroup(replacing: .toolbar) {
                    Button("放大缩略图") {
                        MainWindowCoordinator.performZoom(delta: 1)
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("缩小缩略图") {
                        MainWindowCoordinator.performZoom(delta: -1)
                    }
                    .keyboardShortcut("+", modifiers: .command)
                }
                CommandGroup(replacing: .sidebar) {}
            }

            // MARK: - 壁纸菜单
            CommandMenu("壁纸") {
                Button("设为当前壁纸") {
                    MainWindowCoordinator.menuSetAsWallpaper()
                }
                .keyboardShortcut(.return, modifiers: [])

                Divider()

                Button("切换下一张") {
                    MainWindowCoordinator.menuNavigate(.next)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("切换上一张") {
                    MainWindowCoordinator.menuNavigate(.previous)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("收藏 / 取消收藏") {
                    MainWindowCoordinator.menuToggleFavorite()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("添加标签") {
                    MainWindowCoordinator.menuAddTag()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("查看信息") {
                    MainWindowCoordinator.menuShowInfo()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("预览") {
                    MainWindowCoordinator.menuPreview()
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("查看文件") {
                    MainWindowCoordinator.menuRevealInFinder()
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
