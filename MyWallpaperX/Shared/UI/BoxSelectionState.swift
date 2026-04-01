//
//  BoxSelectionState.swift
//  MyWallpaperX
//
//  框选状态机，三模块网格容器共用。
//  将框选的模式（select/deselect）和初始选中快照封装在一处，
//  消除各模块容器视图中重复的私有状态变量。
//

import Foundation

/// 框选操作的状态机。
/// 在 beginBoxSelection 时初始化，endBoxSelection 时重置。
struct BoxSelectionState {

    /// 框选模式：开始时根据起始点是否已选中决定。
    enum Mode {
        /// 拖拽经过的卡片加入选中
        case select
        /// 拖拽经过的卡片取消选中
        case deselect
    }

    /// 当前框选模式
    let mode: Mode

    /// 框选开始时的选中 ID 快照，用于计算最终选中集合
    let initialIDs: Set<String>

    /// 根据当前框选矩形内的 ID 计算最终选中集合。
    /// - Parameter touchedIDs: 当前框选矩形内的所有 ID
    /// - Returns: 合并后的最终选中集合
    func resolve(touching touchedIDs: Set<String>) -> Set<String> {
        var result = initialIDs
        switch mode {
        case .select:   result.formUnion(touchedIDs)
        case .deselect: result.subtract(touchedIDs)
        }
        return result
    }
}
