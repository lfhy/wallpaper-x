//
//  ContentViewSupport.swift
//  MyWallpaperX
//

import SwiftUI
import QuickLook
import QuickLookUI
import AppKit

enum SelectedItem: Hashable {
    case category(Category)
    case tag(String)
}

extension Notification.Name {
    static let appKitRequestScrollToTopForCurrentSelection = Notification.Name("AppKitRequestScrollToTopForCurrentSelection")
    static let appKitLibraryGridScrollToTopAnimationWillStart = Notification.Name("AppKitLibraryGridScrollToTopAnimationWillStart")
    static let appKitLibraryGridScrollToTopAnimationDidEnd = Notification.Name("AppKitLibraryGridScrollToTopAnimationDidEnd")
}

struct DetailView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    var body: some View {
        // 详情区只根据当前选中项切换“设置页 / 壁纸网格”两条渲染路径，不在此层复制业务状态。
        let selection = selectedItem.selectionContext
        Group {
            if selection.isSettings {
                AppKitSettingsView()
            } else {
                AppKitLibraryGridView(
                    wallpapers: wallpaperManager.sortedWallpapers(
                        selection.sourceWallpapers(from: wallpaperManager),
                        selectionKey: selection.scrollPersistenceKey
                    ),
                    animatesReorder: selection == .category(.recentlyUsed),
                    animatesInsertDelete: selection != .category(.recentlyUsed)
                )
                .id(selection.scrollPersistenceKey)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var previewURL: URL?
    
    private override init() {
        super.init()
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    @discardableResult
    func openPreview(for wallpaper: VideoWallpaper?) -> Bool {
        // 打开预览只负责把当前选中项映射到 QL panel，不在这里改选择状态。
        guard let targetURL = previewURLIfAvailable(for: wallpaper) else { return false }
        presentPreview(for: targetURL)
        return true
    }

    func syncVisiblePreview(for wallpaper: VideoWallpaper?) {
        // 仅当预览面板已经可见时才同步内容，避免外部状态变化把面板反复抢开。
        guard isVisible else { return }
        guard let targetURL = previewURLIfAvailable(for: wallpaper) else { return }
        guard previewURL != targetURL else { return }
        presentPreview(for: targetURL)
    }

    private func previewURLIfAvailable(for wallpaper: VideoWallpaper?) -> URL? {
        guard let wallpaper else { return nil }
        let targetURL = URL(fileURLWithPath: wallpaper.path)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
        return targetURL
    }

    private func presentPreview(for targetURL: URL) {
        previewURL = targetURL
        guard let panel = QLPreviewPanel.shared() else {
            return
        }
        // QLPreviewPanel 依赖 dataSource / delegate 持有一致，否则会出现闪现或按键失效。
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    
    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }

        // 这里接管空格/方向键/ESC，避免系统把事件交回主窗口后再次触发预览开关。
        switch event.keyCode {
        case 49: // Space
            closePreview()
            return true
        case 123, 124, 125, 126: // Arrows
            guard WallpaperManager.shared.moveSingleSelectionByArrowKey(event.keyCode, ignoreSearchFieldState: true) else { return true }
            syncVisiblePreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
            return true
        case 53: // ESC
            closePreview()
            return true
        default:
            guard let normalizedArrow = normalizeArrowKeyCode(from: event) else { return false }
            guard WallpaperManager.shared.moveSingleSelectionByArrowKey(normalizedArrow, ignoreSearchFieldState: true) else { return true }
            syncVisiblePreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
            return true
        }
    }

    private func normalizeArrowKeyCode(from event: NSEvent) -> UInt16? {
        if [123, 124, 125, 126].contains(event.keyCode) {
            return event.keyCode
        }
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value else {
            return nil
        }
        switch scalar {
        case 0xF702: return 123 // left
        case 0xF703: return 124 // right
        case 0xF701: return 125 // down
        case 0xF700: return 126 // up
        default: return nil
        }
    }
}
