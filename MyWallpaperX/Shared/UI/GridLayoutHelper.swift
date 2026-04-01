//
//  GridLayoutHelper.swift
//  MyWallpaperX
//
//  三模块共享的网格列数计算工具。
//  各模块传入自己的 zoomOffset，不共享状态。
//

import CoreGraphics

enum GridLayoutHelper {
    /// 根据可用宽度计算基础列数（不含缩放偏移）
    static func baseColumnCount(for width: CGFloat) -> Int {
        if width >= 1200 { return 6 }
        if width >= 900  { return 5 }
        if width >= 600  { return 4 }
        return 3
    }

    /// 叠加缩放偏移后的实际列数，限制在 minCols~maxCols 范围内
    /// - Parameters:
    ///   - width: 网格可用宽度
    ///   - zoomOffset: 用户手动调整的列数偏移（负数=更大卡片，正数=更多列）
    ///   - minCols: 最小列数（默认3，在线库可传2）
    ///   - maxCols: 最大列数（默认6）
    static func columnCount(
        for width: CGFloat,
        zoomOffset: Int,
        minCols: Int = 3,
        maxCols: Int = 6
    ) -> Int {
        max(minCols, min(maxCols, baseColumnCount(for: width) + zoomOffset))
    }

    /// 缩放按钮可用性，返回 (canZoomOut, canZoomIn)
    /// - Parameters:
    ///   - currentOffset: 当前缩放偏移值
    ///   - width: 网格可用宽度
    ///   - minCols: 最小列数
    ///   - maxCols: 最大列数
    static func zoomAvailability(
        currentOffset: Int,
        for width: CGFloat,
        minCols: Int = 3,
        maxCols: Int = 6
    ) -> (canZoomOut: Bool, canZoomIn: Bool) {
        let base = baseColumnCount(for: width)
        let canZoomOut = currentOffset > (minCols - base)
        let canZoomIn  = currentOffset < (maxCols - base)
        return (canZoomOut, canZoomIn)
    }
}
