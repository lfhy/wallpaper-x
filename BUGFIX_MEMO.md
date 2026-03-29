# MyWallpaperX BugFix 备忘录

---

## 已完成修复（精简）

| # | 问题 | 文件 |
|---|------|------|
| 1 | WallpaperSettings CodingKeys 语义错位 | `VideoWallpaper.swift` |
| 2 | VideoFillMode 用中文作 IPC 值 | `VideoWallpaper.swift` / `main.swift` |
| 3 | Daemon 崩溃无退避，CPU 热循环 | `WallpaperEngine.swift` |
| 4 | autoSwitchTimer 重复注册 RunLoop，切换频率翻倍 | `WallpaperManager+PlaybackSettings.swift` |
| 6 | importPersonalSettings 孤立代码块编译错误 | `WallpaperManager+ProfileSettings.swift` |
| 7 | Manager 侧双重去重冗余 | `WallpaperManager.swift` / `+PlaybackControl.swift` |
| 8 | currentIndex 跨线程写入无保护 | `WallpaperManager+PlaybackControl.swift` |
| 9 | generateCGImage Semaphore 阻塞后台线程 | `WallpaperManager+CachePipeline.swift` |
| 10 | resetStore queue.sync 死锁 + 错误静默 | `WallpaperIndexStore.swift` |
| 12 | pauseAllPlayers/resumeAllPlayers 无主线程保护 | `WallpaperEngine.swift` |
| 17 | wallpaperDetailInfoText Task 生命周期脱钩 | `WallpaperLibrarySupport.swift` |
| — | WallpaperManager+Persistence 引用已删变量编译报错 | `+Persistence.swift` |
| — | AVAsset 废弃同步 API 改异步 | `WallpaperLibrarySupport.swift` / `main.swift` |
| — | SidebarComponents defer 警告 | `SidebarComponents.swift` |

---

## 待修复（后续 Sprint）

| # | 问题 | 严重程度 |
|---|------|----------|
| 16 | DaemonCommand/Event 两处独立定义 | 🟢 低 |

---

## 修复日志（最新在上）

| 时间 | # | 操作 |
|------|---|------|
| 2026-03-28 | 13 | importPersonalSettings 文件检查改为 FileManager 直调，移除主线程normalizedSourcePathExists 累积 I/O |
| 2026-03-28 | 15 | appendWallpapersInBatches 改为一次性 append，消除递归 async 累积调度帧 |
| 2026-03-28 | CachePipeline | generateCGImage 改用 generateCGImageAsynchronously + Semaphore（回调派独立队列），消除 macOS 15 copyCGImage 废弃警告 |
| 2026-03-28 | 16 | 新建 DaemonProtocol.swift 统一 DaemonCommand/DaemonEvent，WallpaperEngineTypes.swift 移除重复定义，main.swift 移除 private struct，DaemonEvent 改为 Codable，naturalVideoSize 改用 presentationSize 消除废弃 API |
| 2026-03-28 | 13 | importPersonalSettings 文件检查改为 FileManager 直调，移除 normalizedSourcePathExists 主线程累积 I/O |
| 2026-03-28 | 15 | appendWallpapersInBatches 改为一次性 append，消除递归 async 累积调度帧 |
| 2026-03-28 | 12 | pauseAllPlayers/resumeAllPlayers 加 assert(Thread.isMainThread) |
| 2026-03-28 | 10 | resetStore 改 queue.async，错误改 NSLog |
| 2026-03-28 | 9 | generateCGImage 改 copyCGImage 同步 API |
| 2026-03-28 | 7 | 删除 Manager 侧去重变量和 guard 块 |
| 2026-03-28 | 6 | 恢复 if let existingIndex 保护结构 |
| 2026-03-28 | 4 | Timer 改手动创建只注册 .common |
| 2026-03-28 | 3 | 指数退避（0→30s），ready 事件归零计数 |
| 2026-03-28 | 1/2 | 确认已修复（CodingKeys / ipcValue） |
