//
//  MyWallpaperApp.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case playback
    case experience
    case controls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playback: return "播放"
        case .experience: return "体验"
        case .controls: return "控制"
        }
    }

    var symbolName: String {
        switch self {
        case .playback: return "play.circle"
        case .experience: return "switch.2"
        case .controls: return "keyboard"
        }
    }

    var sections: Set<AppSettingsSection> {
        switch self {
        case .playback:
            return [.playbackModes, .audio]
        case .experience:
            return [.system, .efficiency, .display]
        case .controls:
            return [.hotkeys, .maintenance]
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let targetSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: nsView)
        }
    }

    private func configureWindowIfNeeded(for view: NSView) {
        guard let window = view.window else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = targetSize

        let currentSize = window.contentLayoutRect.size
        let widthDelta = abs(currentSize.width - targetSize.width)
        let heightDelta = abs(currentSize.height - targetSize.height)
        if widthDelta > 24 || heightDelta > 24 {
            window.setContentSize(targetSize)
            window.center()
        }
    }
}

private struct SettingsSceneView: View {
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @State private var selectedTab: SettingsTab = .playback

    private let targetWindowSize = NSSize(width: 500, height: 440)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbolName)
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 72, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            AppKitSettingsView(visibleSections: selectedTab.sections)
                .environmentObject(wallpaperManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(SettingsWindowConfigurator(targetSize: targetWindowSize))
        .frame(width: targetWindowSize.width, height: targetWindowSize.height)
    }
}

struct AppSettingsCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("偏好设置") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@main
struct MyWallpaperApp: App {
    @StateObject private var wallpaperManager = WallpaperManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
    }
    
    var body: some Scene {
        Settings {
            SettingsSceneView()
                .environmentObject(wallpaperManager)
        }
        .commands {
            AppSettingsCommands()

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
