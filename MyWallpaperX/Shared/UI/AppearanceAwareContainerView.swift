//
//  AppearanceAwareContainerView.swift
//  MyWallpaperX
//
//  监听系统外观切换（深色/浅色模式），通过回调通知持有者刷新主题相关颜色。
//  三个模块的卡片容器都需要此能力，统一在 Shared 层定义，避免重复实现。
//

import AppKit

/// 能感知 effectiveAppearance 变化的 NSView 容器。
/// 将此类用作卡片容器的基类，当系统切换深色/浅色模式时会收到回调。
final class AppearanceAwareContainerView: NSView {
    /// 系统外观发生变化时触发，持有者在此回调中刷新 layer 颜色等主题相关属性。
    var appearanceDidChangeHandler: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChangeHandler?()
    }
}
