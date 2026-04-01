# MyWallpaperX 框架架构备忘

> 最后更新：2026-04-01
> 基准 Git 分支：`dev`

本备忘录作为后续构建唯一参考。如有不合理之处可与用户讨论后修正。

---

## 一、目录结构

```
MyWallpaperX/
├── MyWallpaperX/               ← 主 App Target
│   ├── App/                    ← 窗口生命周期、菜单、状态栏
│   ├── Core/
│   │   ├── Playback/           ← 视频播放引擎 + DaemonProtocol（双 Target 共享）
│   │   └── System/             ← GlobalHotkeyManager、SystemMonitor
│   ├── Models/                 ← 共享数据模型，零依赖
│   ├── Modules/
│   │   ├── VideoLibrary/       ← 已完成，其他模块的实现标准
│   │   ├── StaticImageLibrary/ ← 已完成
│   │   └── OnlineLibrary/      ← 已完成
│   ├── Resources/Videos/
│   ├── Shared/
│   │   ├── UI/                 ← 见下表
│   │   └── Components/         ← SidebarComponents、AppKitSettingsComponents
│   └── Shell/                  ← 路由、侧边栏、窗口框架
├── WallpaperDaemonSources/main.swift  ← 独立进程，不动
├── MyWallpaperXHelp/
└── docs/
```

### Shared/UI/ 文件清单

| 文件 | 内容 |
|------|------|
| `ModalPresentation.swift` | 统一弹窗工厂（`makeAppAlert`/`presentAppAlert`） |
| `UIInteractionAnimation.swift` | 卡片动画常量（hover/press/timing） |
| `GridLayoutHelper.swift` | 网格列数计算，支持 `minCols`/`maxCols` 参数化 |
| `WallpaperGridIdentifiable.swift` | 网格 CollectionView 的 hit-test 标识协议 |
| `GridCollectionViewProtocol.swift` | CollectionView 标准 handler 接口（各模块子类遵从） |
| `BoxSelectionState.swift` | 框选状态机（mode + initialIDs + resolve） |
| `ThumbnailCache.swift` | 异步缩略图缓存（in-flight 合并 + NSCache，后台解码，主线程回调） |
| `AppearanceAwareContainerView.swift` | 监听深色/浅色模式切换的容器基类 |
| `NSViewExtensions.swift` | `isDarkAppearance`、`ensureLayerAnchorCentered` |
| `ModuleFocusable.swift` | 模块焦点协议、`moduleDidBecomeActive` 通知名、`ModuleIdentifier` 枚举 |

---

## 二、依赖层级（严格单向，禁止反向）

```
Daemon → DaemonProtocol（双 Target 共享，新增 IPC 字段只改此文件）
Core   → Models
Shared → Models
Modules/VideoLibrary       → Core、Models、Shared
Modules/StaticImageLibrary → Models、Shared
Modules/OnlineLibrary      → Models、Shared
Shell  → VideoLibrary(WallpaperManager)、Shared、Models
App    → Shell、Core/System、Shared（不直接引用模块内部类型）
```

**核心原则：删除任意一个模块文件夹，其余代码正常编译运行。**

---

## 三、新模块接入规范

三个模块均已完成接入，以下为规范说明，供后续新模块参考。

### 3.1 路由（Shell/ContentViewSupport.swift）

在 `SelectedItem` 枚举追加 case，在 `DetailView.body` 的 `else if selection.isSettings` 之前追加路由分支。`SidebarNode.selectedItem` 属性负责节点 kind → `SelectedItem` 的映射，新增 kind 时必须同步更新。

**子页面归并规范：** 若新节点属于某模块的子页面（而非独立模块），不需要新增 `ActiveModule` case。在 `syncManagerSelection` 中将该节点的 `newModule` 归并到父模块，并在 `isXxx` 条件里同时包含父节点和子节点，确保工具栏/菜单/快捷键路由与父模块一致。

示例（在线库已下载项）：
```swift
let isOnline = item == .onlineLibrary || item == .onlineDownloads
case .onlineDownloads: newModule = .onlineLibrary  // 子页面归并到父模块
```

### 3.2 侧边栏（Shell/SidebarViews.swift）

在 `SidebarSectionID` 追加新分区 case，在 `rebuildNodes` 中追加分区节点构建。

**当前侧边栏分区顺序（`sections.append` 顺序决定）：**
1. **库**（`.library`）：我的视频 → 特别喜爱 → 最近使用
2. **标签**（`.tags`）：视频库标签，支持拖拽排序
3. **图片壁纸**（`.images`）：我的图片（总库）+ 图片库标签，支持拖拽排序
4. **在线**（`.online`）：在线壁纸、已下载项
   - `onlineLibrary`：在线图库浏览页
   - `onlineDownloads`：已下载项管理页（在线库子页面，`activeModule` 归并为 `.onlineLibrary`）
5. **其他**（`.others`）：设置（始终最底部）

**侧边栏节点计数规范：**
- 有内容计数的入口节点必须在 `SidebarSnapshotSignature` 里包含对应计数字段，否则内容变化时侧边栏不会刷新
- 当前已追踪字段：`wallpaperCount`、`favoriteCount`、`recentCount`、`silTagCounts`、`silWallpapersCount`、`onlineDownloadsCount`
- 新增有计数的节点时，必须同步在 `SidebarSnapshotSignature` 结构体和 `makeSidebarSnapshotSignature` 方法中追加字段，并在所有构造 `SidebarSnapshotSignature` 的地方补全

**侧边栏标签拖拽排序：**
- 视频库标签：拖拽结束后调用 `wallpaperManager.tags = liveTagOrder; wallpaperManager.saveTags()`
- 图片库标签：拖拽结束后调用 `SILService.shared.reorderSILTags(liveSILTagOrder)`
- Pasteboard 写入格式区分：视频库用 `"tag:<tagName>"`，图片库用 `"silTag:<tagName>"`，避免跨分区误拖
- 图片库分区（`.images`）子节点第 0 项始终是「我的图片」主入口，拖拽排序只操作第 1 项起的 silTag 节点，`moveItem` 时行索引需 +1 偏移

**侧边栏选中行样式规范：**
- `SidebarRowView` 覆写 `isEmphasized` 始终返回 `true`，确保焦点转移到内容区后选中行仍保持蓝色
- 不依赖 `NSOutlineView` 的默认失焦变灰行为

### 3.3 工具栏（Modules/VideoLibrary/Toolbar/VideoLibraryToolbarController.swift）

**工具栏中心化协调协议（重要）：**
1. **主控权归属**：`VideoLibraryToolbarController` 是工具栏的唯一 `NSToolbarDelegate` 和布局管理者。**禁止**任何子模块控制器直接调用 `toolbar.removeItem` 或 `toolbar.insertItem`。
2. **布局切换触发**：由主控器监听模块切换通知，统一执行 `applyIdentifiers`。子模块仅提供 `identifiers` 列表、`makeItem` 实现，以及自身的轻量模式状态同步。
3. **幂等保护**：布局切换前必须比对当前 `items`，若一致则跳过重绘，避免闪烁。
4. **回退逻辑**：当所有非视频库模块均未激活时，主控器负责恢复默认（视频库）布局。

### 3.4 菜单命令路由与验证（App/MainWindowCoordinator.swift + App/AppDelegate.swift）

**菜单命令分发：** 所有菜单命令经 `MainWindowCoordinator` 分发，不直接调用模块 Service。新模块操作在对应分发方法中追加 `case`。搜索聚焦需在模块 `ToolbarController` 实现 `focusSearch()`，并在 `VideoLibraryToolbarController.focusSearch()` 末端追加分支。

**菜单项可用状态验证（重要）：**

SwiftUI `CommandMenu`/`CommandGroup` 的 `@CommandsBuilder` 闭包**不支持**状态追踪，`.disabled()` 只在 App 启动时求值一次，之后永不更新。**禁止**在 Commands 闭包里用 `.disabled()` 做动态模块判断。

正确做法：由 `AppDelegate` 实现 `NSMenuItemValidation` 协议，在 `validateMenuItem(_:)` 里按 `menuItem.title` 匹配，读取 `MainWindowCoordinator.activeModule` 和各模块 Service 的即时状态返回 `Bool`。AppKit 每次菜单打开时自动调用此方法。

```swift
// AppDelegate 正确示例
func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let module = MainWindowCoordinator.activeModule
    switch menuItem.title {
    case "视频库专属菜单项": return module == .videoLibrary
    case "图片库专属菜单项": return module == .staticImageLibrary
    default: return true
    }
}
```

`MyWallpaperApp.swift` 里的 Commands 闭包只负责定义快捷键绑定和调用动作，**不加任何 `.disabled()`**。

**各模块菜单命令支持对照（新模块接入时参考）：**

| 命令方法 | 视频库 | 图片库 | 在线库（浏览页） | 在线库（已下载项） | 说明 |
|----------|--------|--------|-----------------|-------------------|------|
| `menuImport` | ✅ 导入视频 | ✅ 导入图片 | ✗ break | ✗ break | 在线库无本地导入 |
| `menuCreateTag` | ✅ | ✅ | ✗ break | ✗ break | 在线库无标签系统 |
| `menuAddTag` | ✅ | ✅ | ✗ break | ✗ break | 同上 |
| `menuShowInfo` | ✅ | ✅ | ✗ break | ✅（单选时可用） | 在线库浏览页无本地元数据，已下载项支持信息弹窗 |
| `menuRevealInFinder` | ✅ | ✅ | ✅ 刷新在线列表 | ✅ 查看文件 | 通过 `OnlineDownloadsBridge.isActive` 区分浏览页/已下载项 |
| `menuToggleMultiSelect` | ✅ | ✅ | ✗ break | ✅（已接入 Bridge） | |
| `menuSelectAll` | ✅ | ✅ | ✗ break | ✅（已接入 Bridge） | |
| `menuDeleteSelected` | ✅ | ✅ | ✗ break | ✅（已接入 Bridge） | |
| `menuFocusSearch` | ✅ | ✅ | ✅ | ✅ | |

**`validateMenuItem` 中导入菜单项处理规范：**
```swift
if menuItem.title == "导入" || menuItem.title == "导入视频" || menuItem.title == "导入图片" {
    if module == .staticImageLibrary { menuItem.title = "导入图片"; return true }
    if module == .onlineLibrary      { menuItem.title = "导入";      return false }  // 禁用
    menuItem.title = "导入视频"; return true
}
```
新增模块时，按此模式在 `validateMenuItem` 中处理标题和可用性。

`MainWindowCoordinator.activeModule` 由 `MainWindowController.observeModuleModeChanges` 在模块切换时同步更新，两处（`MainWindowController.activeModule` 和 `MainWindowCoordinator.activeModule`）必须保持一致。

### 3.5 CollectionView 接入 Shared 标准

```swift
final class XxxCollectionView: NSCollectionView, GridCollectionViewProtocol {
    var onBackgroundLeftClick: (() -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var cardInteractionHandler: (() -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    var isBoxSelectionEnabled = false
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)?
    var boxSelectionUpdateHandler: ((NSRect) -> Void)?
    var boxSelectionEndHandler: (() -> Void)?
    private(set) var lastPrimaryClickIndexPath: IndexPath?
}
```

框选用 `BoxSelectionState`，缩略图用 `ThumbnailCache(label:)`，外观容器用 `AppearanceAwareContainerView`。

⚠️ **特例**（已更新）：OnlineLibrary 已于 2026-03-31 从纯 SwiftUI `LazyVGrid` 迁移到 AppKit `NSCollectionView`（`AppKitOLBrowserGridView` / `AppKitOLBrowserContainerView`），并已接入 `ModuleFocusable`。当前在线库浏览页与已下载项页面均通过容器视图监听 `moduleDidBecomeActive` 自动接管焦点。`BoxSelectionState` 和框选功能在线库暂不需要，不视为违规。

### 3.6 模块焦点管理（AppKit 模块必须实现）

```swift
final class XxxGridContainerView: NSView, ModuleFocusable {
    func requestFocus() { window?.makeFirstResponder(collectionView) }
    // 在 init 中注册：
    // NotificationCenter.default.addObserver(forName: .moduleDidBecomeActive, ...) { [weak self] n in
    //     guard module == ModuleIdentifier.xxx.rawValue else { return }
    //     self?.requestFocus()
    // }
}
```

`moduleDidBecomeActive` 由 Shell 层在模块切换后 **120ms** 延迟发出（给工具栏重建留时间）。在线库已迁移到 AppKit 容器并实现该协议：浏览页与已下载项均可接管焦点。纯 SwiftUI 页面若未桥接 AppKit 容器，暂无法接入该协议。

### 3.7 QuickLook

- 视频库：`QuickLookPreviewController.shared`，Space/ESC 由 `MainWindowController.handleQuickLookKeyDown` 处理
- 图片库：`SILQuickLookController.shared` + `SILKeyboardHandler.shared`，`activeModule == .staticImageLibrary` 时接管
- 在线库：**不接入 QuickLook**（远程 URL，QLPreviewPanel 无法预览）

`beginPreviewPanelControl` / `endPreviewPanelControl` 根据 `activeModule` 挂载对应控制器。

---

## 四、Shared 层维护规范

**可以放入：** 无业务状态的纯函数/常量、只接受基本类型的 UI 原语、通用弹窗工厂、`AppearanceAwareContainerView`、零依赖 NSView 扩展、三模块共用的协议/状态机/缓存。

**禁止放入：** 引用任何模块 Service 的代码、模块特定业务逻辑、需要 `@EnvironmentObject`/`@ObservedObject` 注入的视图。

**修改原则：**
- 修改必须对所有模块无破坏
- 只对一个模块有意义的修改放模块内部
- 调整动画常量 → 模块内用局部常量覆盖，不改 `UIInteractionAnimation`
- 调整列数范围 → 通过 `minCols`/`maxCols` 参数传入，不在 `GridLayoutHelper` 加模块分支
- `ThumbnailCache` 不支持取消单条预取，如需此功能在模块内自行扩展

---

## 五、模块边界关键设计点

**各模块 setAsWallpaper 边界**
- VideoLibrary：经过 `WallpaperEngine`，支持视频循环播放，是唯一有权发出播放指令的模块
- StaticImageLibrary：**纯浏览，不提供设置壁纸功能**，不触发任何壁纸设置调用
- OnlineLibrary：**纯浏览平台资源，自身不调用任何壁纸设置接口，不直接依赖视频库模块**。"设为壁纸"的正确流程：
  1. `OnlineLibraryService` 下载视频到本地
  2. 发送 `Notification.Name.onlineVideoReadyToPlay` 通知（`userInfo["localURL": URL]`），定义在 `Shell/ContentViewSupport.swift`
  3. `MainWindowCoordinator.observeOnlineVideoReadyToPlay()` 接收并中转，调用 `WallpaperManager.processImportedVideos(context: .onlinePlayback)`
  4. 视频库静默导入后通过 `setAsWallpaper(_:userInitiated:true)` 直接触发播放（绕过防抖，确保每次点击立即响应）

  **模块间依赖：** OnlineLibrary 只依赖 Foundation（发通知），对 VideoLibrary 零耦合。

  ⚠️ **注意**：播放触发使用 `setAsWallpaper(_:userInitiated:true)` 而非 `requestSetAsWallpaper`，绕过防抖和重复路径跳过逻辑，确保每次点击都立即响应。

**`ImportContext` 使用规范（`WallpaperLibrarySupport.swift`）**

| case | 用途 | 弹窗 | 播放触发 |
|------|------|------|----------|
| `.library` | 用户手动导入到视频库 | ✅ 显示导入结果 | ✗ |
| `.favorites` | 导入并自动收藏 | ✅ 显示导入结果 | ✗ |
| `.tag(String)` | 导入并自动打标签 | ✅ 显示导入结果 | ✗ |
| `.onlinePlayback` | 在线库静默下载后导入 | ✗ 跳过弹窗 | ✅ 立即播放 |

新增 context case 时，必须同步在 `applyContextMetadataIfNeeded` 和 `applyPreparedImportResult` 两处处理。

**UIActionHelper**（`Shell/UIActionHelper.swift`）仅服务视频库。图片库和在线库各自在模块内实现 ActionHelper，不复用此文件。

**通知名定义位置**
- `staticImageLibraryModeDidChange`、`onlineLibraryModeDidChange`：`Shell/ContentViewSupport.swift`
- `moduleDidBecomeActive`：`Shared/UI/ModuleFocusable.swift`
- 模块内部通知：定义在各自模块目录内，不外漏到 Shell/Shared

**跨模块操作请求协议（零耦合中转规范）**

模块间禁止直接调用对方 Service。若某模块需要触发另一模块的操作，必须通过通知中转：

1. 通知名定义在 `Shell/ContentViewSupport.swift`（Notification.Name 扩展）
2. 发出方只负责 post 通知 + userInfo 携带必要参数，不 import 目标模块
3. `MainWindowCoordinator` 在 `configure(with:)` 中注册监听，调用目标模块 Service

**当前已注册的跨模块通知：**

| 通知名 | 发出方 | 接收方 | userInfo | 用途 |
|--------|--------|--------|----------|------|
| `onlineVideoReadyToPlay` | OnlineLibraryService | MainWindowCoordinator | `["localURL": URL]` | 在线库视频下载完成后，由视频库静默导入并播放 |

**模块内部通知（OnlineLibrary，不外漏到 Shell/Shared）：**

| 通知名 | 用途 |
|--------|------|
| `olDownloadsDeleteSelected` | Bridge → Container 删除选中 |
| `olDownloadsSelectAll` | Bridge → Container 全选 |
| `olDownloadsToggleMultiSelect` | Bridge → Container 切换多选 |
| `olDownloadsPreviewSelected` | Bridge → Container QuickLook 预览 |
| `olDownloadsSetAsWallpaper` | Bridge → Container 设为壁纸 |

**`OnlineDownloadsBridge.isActive` 规范：**
- `AppKitOLDownloadsContainerView` 在 `viewDidMoveToWindow()` 中管理此标志
- 接入窗口时设为 `true`，移出时设为 `false`
- `MainWindowCoordinator` 在 `onlineLibrary` 分支调用 Bridge 方法前，先检查 `isActive`，防止误触浏览页

**新模块若需触发其他模块操作，必须遵循此协议，不得直接引用目标模块类型。**

**菜单命令路由**
- `MainWindowCoordinator.activeModule` — 当前激活模块，`MainWindowController` 和 `MainWindowCoordinator` 两处同步维护
- 菜单项可用状态由 `AppDelegate.validateMenuItem` 负责，按 `menuItem.title` 匹配，**不使用** SwiftUI `.disabled()`（见 §3.4）

**各模块快捷键支持情况：**

| 快捷键 | 视频库 | 图片库 | 在线库（浏览页） | 在线库（已下载项） |
|--------|--------|--------|-----------------|-------------------|
| Cmd+E 多选 | ✅ | ✅ | ✗ | ✅（已接入 Bridge） |
| Cmd+A 全选 | ✅ | ✅ | ✗ | ✅（已接入 Bridge） |
| Cmd+Delete 删除 | ✅ | ✅ | ✗ | ✅（已接入 Bridge） |
| Cmd+F 搜索 | ✅ | ✅ | ✅ | ✗（无搜索框） |
| Cmd+I 信息 | ✅ | ✅ | ✗ | ✅（单选时可用） |
| Cmd+R 查看文件/刷新 | ✅ 查看文件 | ✅ 查看文件 | ✅ 刷新在线列表 | ✅ 查看文件 |
| Cmd+D 收藏 | ✅ | ✗ | ✗ | ✗ |
| Cmd+T 标签 | ✅ | ✅ | ✗ | ✗ |
| Return 设为壁纸 | ✅ | ✗ | ✗ | ✅（CollectionView 内已实现） |
| Space QuickLook | ✅ | ✅ | ✗ | ✅（OLDownloadsQuickLookController） |
| 方向键导航 | ✅ | ✅ | ✗ | ✅（CollectionView 内已实现） |
| Cmd+←→ 切换壁纸 | ✅ | ✗ | ✗ | ✗ |

---

## 六、工具栏控制器协作机制

```
VideoLibraryToolbarController（主控，NSToolbarDelegate）
    ├── toolbar(_:itemForItemIdentifier:) default 分支依次代理给：
    │       OnlineLibraryToolbarController.makeItem(for:)
    │       SILToolbarController.makeItem(for:)
    ├── lazy var onlineLibraryToolbarController
    └── lazy var staticImageLibraryToolbarController
```

各子控制器可以监听模式切换通知更新自身状态与按钮内容，但**不得直接修改 `NSToolbar` 布局**；布局切换只能由 `VideoLibraryToolbarController.applyIdentifiers` 执行。

`performZoom(delta:)` 路由链：`MainWindowCoordinator` → `MainWindowController` → `VideoLibraryToolbarController` → 各子控制器。  
`focusSearch()` 路由链：`MainWindowCoordinator` → `VideoLibraryToolbarController` → 各子控制器。

---

## 七、缩放控件语义（重要，新模块必须遵守）

本项目缩放采用**故意的反直觉映射**，这是产品设计要求，不是 bug，**不要修正**：

| 菜单项 | 快捷键 | delta | 实际效果 |
|--------|--------|-------|----------|
| 放大缩略图 | Cmd+- | `+1` | 列数增加，卡片变小 |
| 缩小缩略图 | Cmd++ | `-1` | 列数减少，卡片变大 |

新模块缩放按钮的 segment 图标顺序可自由选择，但 handler 传入 `performZoom(delta:)` 的参数必须遵守以上语义。

`GridLayoutHelper.zoomAvailability` 用于计算按钮可用性，各模块传入自己的 `zoomOffset`，互相独立。

---

## 八、框架层巡检与模块接入验收清单

### 8.1 框架层日常巡检（统筹层执行）

1. **路由一致性巡检**
   - `SelectedItem` case 与 `DetailView` 路由分支一一对应
   - `ContentView.syncManagerSelection` 的 `newModule` 归并与子页面归属一致（如 `onlineDownloads -> .onlineLibrary`）
   - `SidebarNode.selectedItem` 与侧边栏节点 kind 映射一致

2. **菜单一致性巡检**
   - `MyWallpaperApp` Commands 仅定义动作与快捷键，不使用动态 `.disabled()`
   - `MainWindowCoordinator` 负责全部菜单命令分发
   - `AppDelegate.validateMenuItem(_:)` 负责动态可用性与标题切换

3. **焦点一致性巡检**
   - 模块容器遵循 `ModuleFocusable`
   - 模块激活后响应 `moduleDidBecomeActive` 并执行 `requestFocus()`
   - 焦点通知时序与工具栏重建时序保持兼容（当前延迟 120ms）

4. **跨模块协作巡检**
   - 跨模块请求仅走通知中转：通知定义在 Shell，执行在 Coordinator
   - 模块间不得直接 import 目标模块 Service

### 8.2 新模块/子页面接入验收（模块负责人 + 统筹层）

- [ ] Shell 路由已接入（`SelectedItem`、`DetailView`、`syncManagerSelection`）
- [ ] Sidebar 节点与计数已接入（含 `SidebarSnapshotSignature`）
- [ ] 工具栏模式通知已接入（含子页面 `isDownloads` 等上下文）
- [ ] 菜单分发与可用性验证已接入（Coordinator + AppDelegate）
- [ ] 焦点协议已接入（`ModuleFocusable` + 激活通知）
- [ ] 跨模块调用遵循“通知 + 中转”零耦合规范

### 8.3 文档维护制度

以下变更发生时，必须同步维护本备忘录：
- 新增/删除模块或子页面
- 路由映射与 activeModule 归并规则变化
- 通知协议（名称、payload、中转路径）变化
- 菜单命令分发或 `validateMenuItem` 规则变化
- 焦点接管机制变化

若发生真实框架缺陷修复（非纯文档改写），同时在 `docs/framework-fix-archive.md` 追加 FIX 记录。

---

## 九、待处理技术债

| 编号 | 问题 | 影响 |
|------|------|------|
| TD-1 | `VideoLibraryToolbarController.configureZoomItem()` 内联了 `GridLayoutHelper` 等价计算，未复用共享方法 | 仅代码重复，行为正确 |
| TD-2 | OnlineLibrary 浏览页焦点接管曾缺失 | **已修复（2026-03-31）**：`AppKitOLBrowserContainerView` 迁移到 AppKit 后已接入 `ModuleFocusable`，浏览页和已下载项均可自动接管焦点 |
| TD-5 | `OnlineLibraryBrowserView.swift` 中 `OLDownloadedView`、`OLVideoCard` 为废弃遗留代码，已被侧边栏「已下载项」子页面替代 | 纯死代码，增加维护负担，待模块负责人确认后删除 |
| TD-3 | `ContentView.syncManagerSelection` 中 `silTag` 判断用了立即执行尾随闭包，可读性差 | 仅可读性问题，逻辑正确 |
| TD-4 | ~~`OnlineLibraryService` 直接调用 `NSWorkspace.shared.setDesktopImageURL`~~ | **已修复（2026-03-31）**：改为通知中转 → `processImportedVideos(context: .onlinePlayback)` → `setAsWallpaper(_:userInitiated:true)`，全程无弹窗，模块间零耦合 | 
