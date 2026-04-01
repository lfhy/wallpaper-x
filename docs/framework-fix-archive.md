# MyWallpaperX 框架修复归档

> 已解决的框架层缺陷记录，供回溯查阅。日常开发无需阅读此文档。

---

## FIX-1｜MainWindowCoordinator.activeModule 缺少回退逻辑

**日期：** 2026-03-30  
**症状：** 从图片库/在线库切回视频库后，Cmd+E / Cmd+A / Cmd+Delete / Cmd+I 等快捷键失效或行为错误。  
**根因：** `MainWindowCoordinator.activeModule` 只在 `enabled:true` 时被更新，`enabled:false` 时从未回退，导致 Coordinator 的模块状态永远停留在上一个非视频库模块。菜单命令的 `disabled` 判断因此持续按旧模块路由。  
**修复：**
- `MainWindowCoordinator` 新增 `clearActiveModuleIfMatches(_:)` 方法
- `MainWindowController.observeModuleModeChanges` 的 `enabled:false` 分支调用此方法，使两处 `activeModule` 同步回退到 `.videoLibrary`

---

## FIX-2｜工具栏被视频库内部切换无效触发重建

**日期：** 2026-03-30  
**症状：** 在视频库内部切换分类时工具栏出现短暂闪烁或延迟，切换频繁时更明显。  
**根因：** `ContentView.syncManagerSelection` 每次 `selectedItem` 变化（包括视频库内分类切换）都无条件发出 `staticImageLibraryModeDidChange(false)` 和 `onlineLibraryModeDidChange(false)`，导致 `SILToolbarController` 和 `OnlineLibraryToolbarController` 反复执行 `removeItem`/`insertItem` 工具栏重建。  
**修复：**
- `ContentView` 新增 `@State lastPostedModuleID: ModuleIdentifier`
- 仅在模块真正跨类切换时才发通知（幂等保护）
- `wallpaperManagerDidResetToFreshInstallState` 时同步重置该状态

---

## FIX-3｜焦点通知时机过早导致快捷键偶发失效

**日期：** 2026-03-30  
**症状：** 切换到图片库后偶发快捷键无响应，需要点击一次网格才恢复。  
**根因：** `moduleDidBecomeActive` 延迟仅 50ms，而工具栏 `applyIdentifiers`（遍历 `removeItem`/`insertItem`）在窗口繁忙时耗时可超过此限。`makeFirstResponder(collectionView)` 在 CollectionView 尚未显示时调用无效，焦点接管失败。  
**修复：** 焦点通知延迟从 50ms 调整为 120ms，给工具栏重建留出足够时间。
