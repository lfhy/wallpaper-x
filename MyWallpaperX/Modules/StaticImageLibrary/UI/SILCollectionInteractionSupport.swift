//
//  SILCollectionInteractionSupport.swift
//  MyWallpaperX
//

import Foundation

enum SILCollectionInteractionSupport {
    static func schedulePressRelease(
        pressedAt: TimeInterval,
        action: @escaping () -> Void
    ) -> DispatchWorkItem {
        let elapsed = ProcessInfo.processInfo.systemUptime - pressedAt
        let remaining = max(0, UIInteractionAnimation.minimumPressVisualDuration - elapsed)
        let workItem = DispatchWorkItem(block: action)
        if remaining <= 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
        }
        return workItem
    }
}
