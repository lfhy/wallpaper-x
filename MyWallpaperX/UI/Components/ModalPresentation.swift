//
//  ModalPresentation.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import AppKit

func appModalHostWindow() -> NSWindow? {
    // 弹窗优先挂到主窗口，其次才是当前 key/main window，避免 sheet 跑到错误窗口上。
    MainWindowCoordinator.mainWindow() ?? NSApp.keyWindow ?? NSApp.mainWindow
}

func makeAppAlert(
    title: String,
    message: String = "",
    style: NSAlert.Style = .informational,
    buttons: [String] = ["确定"],
    accessoryView: NSView? = nil
) -> NSAlert {
    // 统一工厂方法保证所有警告/确认弹窗都走同一套按钮与样式初始化。
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message
    buttons.forEach { alert.addButton(withTitle: $0) }
    alert.accessoryView = accessoryView
    return alert
}

private func centeredAlertString(_ text: String, font: NSFont) -> NSAttributedString {
    // 系统对话框文字居中只在这里做一次，避免每个 alert 自己重复拼样式。
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byWordWrapping

    return NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
    )
}

extension NSAlert {
    func applyAppDialogStyle() {
        // 对话框样式只在一个扩展里统一处理，后续改全局弹窗风格只改这里。
        icon = NSApp.applicationIconImage

        if !messageText.isEmpty {
            setValue(
                centeredAlertString(
                messageText,
                font: .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                ),
                forKey: "attributedMessageText"
            )
        }

        if !informativeText.isEmpty {
            setValue(
                centeredAlertString(
                    informativeText,
                    font: .systemFont(ofSize: NSFont.smallSystemFontSize)
                ),
                forKey: "attributedInformativeText"
            )
        }
    }
}

func presentAppAlert(
    _ alert: NSAlert,
    in window: NSWindow? = nil,
    completion: ((NSApplication.ModalResponse) -> Void)? = nil
) {
    // 先应用统一样式，再决定用 sheet 还是 modal，不把展示策略散到调用方。
    alert.applyAppDialogStyle()

    if let window = window {
        alert.beginSheetModal(for: window, completionHandler: completion)
        return
    }

    let response = alert.runModal()
    completion?(response)
}
