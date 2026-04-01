//
//  SILQuickLookController.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
//  图片库 QuickLook 控制器，参照 QuickLookPreviewController。
//  Space 键打开预览，方向键切换选中项并同步预览内容，ESC/Space 关闭。
//  注意：仅用于预览，不涉及设为壁纸功能
//
import AppKit
import QuickLook
import QuickLookUI

final class SILQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = SILQuickLookController()
    private var previewURL: URL?
    private override init() { super.init() }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func open(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self; panel.delegate = self
        panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }

    func syncVisible() {
        guard isVisible else { return }
        guard let id = SILService.shared.selectedID,
              let w = SILService.shared.wallpapers.first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: w.path)
        guard FileManager.default.fileExists(atPath: url.path), previewURL != url else { return }
        previewURL = url
        QLPreviewPanel.shared()?.reloadData()
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self; panel.delegate = self
    }
    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    // MARK: - QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    // MARK: - QLPreviewPanelDelegate
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let noMod = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        guard noMod else { return false }
        switch event.keyCode {
        case 49, 53: // Space / ESC
            close(); return true
        case 123, 124, 125, 126: // 方向键
            SILService.shared.moveSingleSelectionByArrowKey(event.keyCode)
            syncVisible(); return true
        default: return false
        }
    }
}

// MARK: - 键盘处理器（供 MainWindowController 调用）

final class SILKeyboardHandler {
    static let shared = SILKeyboardHandler()
    private init() {}

    func handleSpace() -> Bool {
        let ql = SILQuickLookController.shared
        if ql.isVisible { return true }
        guard let id = SILService.shared.selectedID,
              let w = SILService.shared.wallpapers.first(where: { $0.id == id }) else { return false }
        ql.open(url: URL(fileURLWithPath: w.path))
        return true
    }

    func handleEsc() -> Bool {
        let ql = SILQuickLookController.shared
        guard ql.isVisible else { return false }
        ql.close(); return true
    }
}
