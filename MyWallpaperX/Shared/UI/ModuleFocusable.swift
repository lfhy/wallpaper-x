//
//  ModuleFocusable.swift
//  MyWallpaperX
//
//  模块焦点管理协议。
//  各模块的根容器视图遵从此协议，Shell 层在模块切换时统一调用，
//  让目标模块把键盘焦点转给正确的内部子视图（CollectionView 等）。
//
//  使用方式：
//  1. 模块容器视图遵从 ModuleFocusable，实现 requestFocus()
//  2. 在 requestFocus() 内调用 window?.makeFirstResponder(内部CollectionView)
//  3. Shell 层通过 moduleDidBecomeActive 通知触发，无需知晓模块内部类型
//

import AppKit

// MARK: - 协议

/// 模块根容器视图遵从此协议，表示该模块可以接管键盘焦点。
protocol ModuleFocusable: NSView {
    /// 模块激活时由框架层调用，实现者负责把焦点给到正确的内部子视图。
    func requestFocus()
}

// MARK: - 通知名

extension Notification.Name {
    /// Shell 层在模块切换完成后发出，object 为目标 SelectedItem 的描述字符串。
    /// userInfo: ["module": String] 标识目标模块
    static let moduleDidBecomeActive = Notification.Name("com.mywallpaper.moduleDidBecomeActive")
}

// MARK: - 模块标识常量

enum ModuleIdentifier: String {
    case videoLibrary       = "videoLibrary"
    case staticImageLibrary = "staticImageLibrary"
    case onlineLibrary      = "onlineLibrary"
}
