//
//  WallpaperGridIdentifiable.swift
//  MyWallpaperX
//
//  Shell 层通过此协议识别「壁纸网格视图」，避免直接引用 VideoLibrary 内部类型。
//  任何实现了网格功能的 NSCollectionView 子类都应遵从此协议。
//

import AppKit

/// 标记协议：表示该视图是一个壁纸网格容器。
/// Shell 层用此协议做 hit-test，各模块的网格视图各自声明遵从，互不依赖。
protocol WallpaperGridIdentifiable: NSView {}
