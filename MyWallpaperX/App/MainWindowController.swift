//
//  MainWindowController.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit
import QuickLookUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let wallpaperManager: WallpaperManager
    private let toolbarController: MainWindowToolbarController
    private var hasShownWindow = false
    private let quickLookPreviewController = QuickLookPreviewController.shared

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        let rootView = ContentView()
            .environmentObject(wallpaperManager)
            .frame(minWidth: 900, minHeight: 650)
        let hostingController = NSHostingController(rootView: rootView)

        let window = MainAppWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        window.title = "MyWallpaperX"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .shadow
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = true
        window.isRestorable = false
        // 主窗口保持普通桌面窗口语义，避免被系统当成辅助浮层窗口处理。
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        // 关闭窗口自动恢复链路，避免 restoreWindowWithIdentifier 相关噪音警告和误恢复。

        self.toolbarController = MainWindowToolbarController(window: window, wallpaperManager: wallpaperManager)
        super.init(window: window)
        shouldCascadeWindows = false
        self.window?.delegate = self
        configureQuickLookKeyHandling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        // 只在首次显隐时居中；后续保持用户手动调整后的窗口位置。
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        MainWindowCoordinator.activate(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        (window as? MainAppWindow)?.quickLookKeyDownHandler = nil
        MainWindowCoordinator.handleWindowWillClose(self)
    }

    private func configureQuickLookKeyHandling() {
        guard let window = window as? MainAppWindow else { return }
        // Quick Look 的键盘入口只放在窗口级别拦截，避免影响文本输入与集合视图默认键行为。
        window.quickLookKeyDownHandler = { [weak self] event in
            self?.handleQuickLookKeyDown(event) ?? false
        }
    }

    private func handleQuickLookKeyDown(_ event: NSEvent) -> Bool {
        // 只接管无修饰键的 Space / ESC，其余按键保持系统与控件默认分发。
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return false
        }
        if isEditingTextInput() {
            return false
        }

        switch event.keyCode {
        case 49: // Space
            if event.isARepeat {
                return true
            }
            if quickLookPreviewController.isVisible {
                return true
            }
            return quickLookPreviewController.openPreview(for: wallpaperManager.selectedWallpaperForQuickLook)
        case 53: // ESC
            if quickLookPreviewController.isVisible {
                quickLookPreviewController.closePreview()
                return true
            }
            return false
        default:
            return false
        }
    }

    private func isEditingTextInput() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        if let textView = keyWindow.firstResponder as? NSTextView, textView.isEditable {
            return true
        }
        return false
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        // Quick Look 面板生命周期由共享控制器接管，窗口本身只负责挂接入口。
        QuickLookPreviewController.shared.attach(to: panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        // 面板关闭时解除引用，防止旧 panel 被意外复用或提前释放后仍持有回调。
        QuickLookPreviewController.shared.detach(from: panel)
    }
}

final class MainAppWindow: NSWindow {
    var quickLookKeyDownHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let quickLookKeyDownHandler,
           quickLookKeyDownHandler(event) {
            return
        }
        super.sendEvent(event)
    }
}
