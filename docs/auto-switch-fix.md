# 自动切换专项修复备忘录

## 用户核心要求

1. **自动切换开启**：立即按设定时间从 0 起算，到时间自动切换下一张，切换后继续严格按设定时间计时。
2. **自动切换关闭**：当前视频不重播、无闪烁，播完当前视频立即切换下一张，之后完全回归主模式逻辑（顺序/随机）。
3. **开关操作无感**：开关切换时画面不重播、不闪烁、不重载。
4. **手动切换重置计时**：自动切换开启时用户手动切换视频，timer 立即从 0 重置。
5. **模式切换重置计时**：随机↔顺序切换时，timer 立即从 0 重置，两模式互不干扰。
6. **视频比计时长**：视频播到计时结束时立即切换（不等视频播完）。
7. **视频比计时短**：视频播完进入下一次循环等待计时，计时到了再切换。

---

## 已确认的错误路径（不要走）

1. **不能用 `setLoopCurrentItem` / `setLoop` IPC 命令动态改 loop 状态**
   - `AVPlayerLooper` 重建会导致视频从头播放。
   - `setLoop` 是异步 IPC，存在竞态。
2. **不能在开关切换时调 `setAsWallpaper` 重载当前视频**
   - 即使有 crossfade，用户能感知到画面重播和闪烁。
3. **`shouldLoopCurrentItemInEngine` 不能依赖 `autoSwitchEnabled`**
   - 循环状态只由主播放模式决定（循环模式=true，顺序/随机=false）。
4. **`refreshAutoSwitchTimerIfNeeded` 不能调 `normalizePlaybackSettings()`**
   - 会触发 `$settings` 订阅副作用链。
5. **`ensureAtLeastOnePlaybackMode` 不能回落到 loop 模式**
   - loop 模式下 timer 会被意外销毁，必须回落到 sequential。
6. **`sequentialAdjacentIndex` 不能只依赖主库 `wallpapers` 原始顺序**
   - 主库顺序是导入顺序，不是用户在网格里看到的排序顺序。
   - 必须用 `sortedWallpapers(wallpapers, selectionKey:)` 排序后的全量列表计算相邻。
   - 同时不能依赖 `sourceWallpapers`（子集），避免 id 映射失败回落 `currentIndex` 切换到自身。
   - 正确做法：`sortedWallpapers(wallpapers)` 全量排序 → 找当前视频在排序列表里的位置 → 计算相邻 → 映射回主库索引。

---

## 当前正确实现（最终版）

### 核心原则
**开关只管 timer，不动引擎，不重载视频，完全无感。**

### `shouldLoopCurrentItemInEngine()` ✅ 最终修复
```swift
// 循环模式：始终循环。
// 自动切换开启的顺序/随机模式：视频循环，等 timer 到期再切换（短视频反复循环等计时）。
// 自动切换关闭的顺序/随机模式：不循环，视频播完由 handlePlaybackEnded 切下一张。
settings.loopPlayback || (settings.autoSwitchEnabled && isSwitchingPlaybackMode())
```

**关键**：开关切换时不重载视频（不调 `setAsWallpaper`），循环状态在下次切换到新视频时自然生效。

### `handleAutoSwitchToggle()`
```swift
if enabled {
    startAutoSwitchTimer()  // 从 0 重建 timer，不动引擎
} else {
    stopAutoSwitchTimer()   // 销毁 timer，不动引擎
}
```

### `timerDidFire()`
```swift
// 按主模式切换，timer repeats:true 自动续计，不重建。
advanceWallpaperForCurrentMode(triggeredByTimer: true)
```

### `handlePlaybackEnded()`
```swift
if settings.autoSwitchEnabled {
    // 视频播完（比计时短）：停旧 timer + 切换 + 重建 timer
    stopAutoSwitchTimer()
    advanceWallpaperForCurrentMode(triggeredByTimer: false)
    startAutoSwitchTimer()
} else {
    // 自动切换关闭：按主模式切下一张
    advanceWallpaperForCurrentMode(triggeredByTimer: false)
}
```

### `setAsWallpaper(userInitiated: true)`
```swift
// 用户手动切换时重置 timer
if settings.autoSwitchEnabled && userInitiated {
    startAutoSwitchTimer()
}
```

### `setRandomPlaybackEnabled` / `setSequentialPlaybackEnabled`
```swift
// 模式切换时重建 timer，不动引擎，不调 setLoopCurrentItem
startAutoSwitchTimer()
```

### `ensureAtLeastOnePlaybackMode`
```swift
// 回落到 sequential，不回落到 loop
if !settings.loopPlayback && !settings.randomPlayback && !settings.sequentialPlayback {
    settings.sequentialPlayback = true
}
```

### `sequentialAdjacentIndex` ✅ 最终修复
```swift
// 直接在主库 wallpapers 里计算相邻索引，不依赖 displayList/sourceWallpapers。
// 原来依赖 currentSelectionContext.sourceWallpapers 会在 favorites/tag 分类下
// 导致 targetWallpaper 在主库找不到，回落 currentIndex，切换到自身。
let currentIdx = currentWallpaper.flatMap { w in
    wallpapers.firstIndex(where: { $0.id == w.id })
} ?? currentIndex
return (currentIdx + 1) % wallpapers.count  // next
return (currentIdx - 1 + wallpapers.count) % wallpapers.count  // previous
```

---

## 根因分析（第二条视频不切换）

**日志证据：**
```
currentIndex=1 targetIndex=1 target=同一个视频
```

**原因链：**
1. `sequentialAdjacentIndex` 用 `currentSelectionContext.sourceWallpapers` 构建 `displayList`
2. 关闭再开启自动切换后，`currentSelectionContext` 可能指向 favorites/tag 分类
3. `currentWallpaper` 在 `displayList` 里找不到（id 不匹配或排序后位置错误）
4. 走 fallback 路径，最终 `targetWallpaper` 在主库 `wallpapers` 里找不到
5. 回落 `?? currentIndex`，targetIndex == currentIndex
6. Engine 判断 `isSameWallpaperRequest && isConfigurationUnchanged = true`，不重发 play
7. 视频不切换，timer 继续 fire，每次都切换到自身

**修复：** 直接在主库 `wallpapers` 里按索引顺序切换，完全绕开 displayList 的复杂性。

---

## 播放列表隔离功能（新需求）

### 核心要求
用户在哪个列表点击播放，后续所有自动切换（顺序/随机/自动切换）都在该列表内进行，不跨列表切换。
- 在「我的壁纸」点击 → 在「我的壁纸」全量列表内循环
- 在「特别喜欢」点击 → 在「特别喜欢」列表内循环
- 在「自定义标签」点击 → 在该标签列表内循环

### 实现思路
- `currentSelectionContext` 已存储用户当前所在的分类/标签。
- `sequentialAdjacentIndex` 和随机播放需要从 `currentSelectionContext.sourceWallpapers` 取播放源，而非全量 `wallpapers`。
- 但之前 sourceWallpapers 有 id 映射失败的问题（回落 currentIndex），需要同时保留排序逻辑。
- 正确做法：source = `sourceWallpapers(from: self)`，sorted = `sortedWallpapers(source, selectionKey:)`，相邻在 sorted 里算，映射回 `wallpapers` 主库用 id 查找。

### 注意
- `setAsWallpaper` 时要记录用户点击时的 `currentSelectionContext`（播放列表来源）。
- 自动切换/手动切换时，从记录的播放列表来源取视频，而非当前 UI 选中的分类。

| 需求 | 状态 | 说明 |
|---|---|---|
| 开启立即计时 | ✅ | `startAutoSwitchTimer()` 从 0 重建 |
| 切换后严格按时间 | ✅ | `repeats:true` 自动续计，不重建 |
| 关闭无感 | ✅ | 只 `stopAutoSwitchTimer()` + `setLoopCurrentItem(false)` |
| 关闭后视频播完切下一张 | ✅ | daemon `setLoop false` 重注册 `pendingEndObservation` |
| 开关无闪烁 | ✅ | 不调 `setAsWallpaper`，不重载视频 |
| 手动切换重置计时 | ✅ | `setAsWallpaper(userInitiated:true)` 里重建 |
| 模式切换重置计时 | ✅ | `setRandomPlaybackEnabled` 里重建 |
| 视频比计时长立即切换 | ✅ | timer 到期直接切，不等视频结束 |
| 视频比计时短循环等计时 | ✅ | `setLoop true` → `loopEndObservation` seek to zero |
| 顺序切换不卡死 | ✅ | 直接用主库索引，不依赖 displayList |
| 关闭后不黑屏 | ✅ | 不调 `clearActiveLooper()`，只移除 loopEndObservation |
| 关闭后不卡最后一帧 | ✅ | `actionAtItemEnd = .pause`，触发 `didPlayToEndTime` |
| setLoop IPC 去重导致命令丢失 | ✅ | 移除 `guard currentShouldLoopCurrentItem != shouldLoop` |
| currentVideoPath 时序错误 | ✅ | `activatePreparedPlayer` 时立即更新，不等动画结束 |

---

## 已确认的额外错误路径

7. **`setLoopCurrentItem` 有 guard 去重会导致命令丢失**
   - 快速开关时，两次相同方向的操作被 guard 过滤，daemon 收不到命令。
   - 修复：移除 guard，每次都强制发送。

8. **`clearActiveLooper()` 在视频播放时调用会黑屏**
   - looper 管理 AVQueuePlayer 队列，清理后队列变空，视频停止播放。
   - 修复：`setLoop false` 时不清理 looper，只移除 `loopEndObservation`。

9. **`actionAtItemEnd = .none` 导致卡最后一帧**
   - `.none` 让视频停在最后一帧但不触发 `didPlayToEndTime`。
   - 修复：改为 `.pause`，播完触发通知。

10. **`currentVideoPath` 在动画结束时才更新，导致 setLoop false 注册到旧视频**
    - timer fire → 切换新视频 → crossfade 动画 → 动画结束才更新 `currentVideoPath`
    - 关闭自动切换在动画期间到达，`setLoop false` 用旧 path 注册 `pendingEndObservation`
    - `playbackEnded` 路径不匹配，`handlePlaybackEnded` 被 guard 忽略，视频卡住
    - 修复：在 `activatePreparedPlayer` 开始时立即更新 `currentVideoPath`，不等动画结束。
