//
//  WallpaperEngineTypes.swift
//  MyWallpaperX
//
//  CGS 私有 API 声明（仅主进程使用，不进入 daemon target）。
//  DaemonCommand / DaemonEvent 已移至 DaemonProtocol.swift（两个 target 共享）。
//

import Foundation

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray
