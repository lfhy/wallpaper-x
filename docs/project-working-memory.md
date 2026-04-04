# Project Working Memory

> 最后更新：2026-04-03
> 维护范围：当前项目事实、用户偏好、重要路径、当前框架与 Steam Workshop 现状

## Product Context
- `MyWallpaperX` 是一个 macOS 动态壁纸软件。
- Steam 创意工坊能力是产品中的工具型模块，不是唯一核心。
- Steam 链路当前目标：
  - 浏览 Wallpaper Engine 创意工坊中的视频类项目
  - 登录 Steam 或匿名浏览
  - 保持登录状态
  - 下载到 `~/Movies/MyWallpaperX/创意工坊`
  - 下载后可从 Steam 下载页触发“设为壁纸”

## User Preferences
- 除非用户明确要求“直接改”，否则先检查、给结论，再等确认。
- 如果用户建议不合理，要主动指出并讨论，不盲从。
- 优先做“最方便、最好用”的方案，而不是理论最完美但工程代价过大的方案。
- Steam 创意工坊浏览页不要内嵌网页，要原生网格 UI。
- 登录页需要客户端化，流程直观。
- 登录状态和网格缓存都要持久化，不能每次返回都丢。

## Architecture Boundary
- 按 `AGENTS.md`，默认优先操作公共层：`App/`、`Shell/`、`Core/`、`Shared/`、`docs/`
- 仅在以下情况进入 `Modules/*`：
  - 模块偏离框架协议，造成跨模块协作问题
  - 模块未按约定接入公共协议
  - 用户明确要求修改模块代码
- 当前 Steam Workshop 功能属于用户明确授权可进入的模块。

## Current Framework Facts
- 主窗口菜单命令统一由 `MainWindowCoordinator` 分发。
- 菜单动态可用性统一由 `AppDelegate.validateMenuItem(_:)` 管理，不在 SwiftUI Commands 中做动态 `.disabled()`。
- 路由与模块归并在 `ContentView.syncManagerSelection(from:)` 完成：
  - `onlineDownloads` 归并到 `.onlineLibrary`
  - `steamDownloads` 归并到 `.steamWorkshop`
- 工具栏布局统一由 `VideoLibraryToolbarController` 主控，子模块工具栏控制器只提供 item 和局部状态同步。
- 模块焦点统一通过 `moduleDidBecomeActive` 通知接管，Shell 当前在模块切换后延迟 120ms 发出通知。
- 跨模块播放请求统一通过通知中转：
  - `onlineVideoReadyToPlay`
  - `steamWorkshopVideoReadyToPlay`

## Current Steam Workshop Design
- 浏览页是原生网格，不直接呈现网页。
- 浏览网格已切到 AppKit `NSCollectionView`。
- 卡片点击后进入原生详情面板，不再依赖网页详情页 UI。
- 浏览页与下载页都已接入工具栏模式切换、侧边栏路由和焦点接管。
- 当前浏览工具栏能力包括：
  - Steam 账号入口
  - 排序源切换
  - 热门时间窗切换
  - 多维筛选
  - 搜索
  - 缩放
  - 作者工坊返回入口
- 当前下载页工具栏能力包括：
  - 打开下载目录
  - 搜索下载项
  - 缩放
  - 刷新

## Current Steam Data Strategy
- 浏览页基础数据仍主要来自 Steam 页面抓取与解析。
- 详情页元数据目前是混合策略：
  - 页面 HTML 解析
  - Steam 官方 `GetPublishedFileDetails` 接口补充字段
- 当前不能再把“没有确认到官方 JSON 接口”视为项目现状；代码里已经接入 `ISteamRemoteStorage/GetPublishedFileDetails/v1/`。
- 预览资源仍主要依赖 `images.steamusercontent.com/ugc/...`。
- 动态缩略图当前仍未确认有独立公开预览接口；现有策略仍以页面资源与详情补水为主。

## Current Steam Authentication / Download Strategy
- 不放弃 SteamCMD。
- 当前采用“随 app 打包内置 SteamCMD 运行时”的方案。
- 运行时基线来自 `SteamCMDRuntime.bundle`。
- 用户态运行时目录当前仍保留在：
  - `~/Library/Application Support/MyWallpaperX/SteamWorkshopRuntime`
- 登录与下载仍围绕 `steamcmd.sh`。
- 当前登录入口已收敛为单一头像菜单：
  - 登录 Steam
  - 匿名浏览
  - 切换账号
  - 退出登录
- 下载内容的最终落地目录是：
  - `~/Movies/MyWallpaperX/创意工坊`
- Steam 下载页扫描最终落地目录并保留本地元数据。

## Important Paths
- 项目根目录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX`
- 当前调试 app 构建产物：
  - `/Users/songziqiang/Library/Developer/Xcode/DerivedData/MyWallpaperX-ezuatvrxfeqxwzeubireydvbdhtc/Build/Products/Debug/MyWallpaperX.app`
- Steam 服务实现：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift`
- Steam 浏览页：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopBrowserView.swift`
- Steam 工具栏控制器：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController.swift`
- 框架备忘录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/docs/framework-architecture-memo.md`
- Steam 缓存目录：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop`
- SteamCMD 认证日志：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- Steam 运行时目录：
  - `/Users/songziqiang/Library/Application Support/MyWallpaperX/SteamWorkshopRuntime`
- Steam 下载目标目录：
  - `~/Movies/MyWallpaperX/创意工坊`

## Current Menu / Shortcut Reality
- Steam 浏览页当前已接入：
  - `Cmd+F` 搜索
  - 缩放快捷键
- Steam 下载页当前已接入：
  - `Cmd+F` 搜索
  - 缩放快捷键
  - 菜单多选
  - 菜单全选
  - 菜单删除
  - 菜单“查看文件”对当前单选下载项执行“在访达中显示”，无选中项或处于多选模式时禁用
  - 菜单“信息”为 toggle 语义：当前单选项 Inspector 已打开时，再次触发同一入口会关闭
- Steam 模块当前仍不接入：
  - QuickLook
  - Return 直接设为壁纸
- Steam 下载页的“设为壁纸”走通知中转到视频库静默导入并播放，不通过视频库菜单命令直接路由。

## Confirmed Historical Findings
- 旧版本在 App Sandbox 下运行 SteamCMD 登录时，曾出现：
  - `CreateBoundSocket: ::bind to port 0 returned error [no name available](1)`
- 旧日志曾确认：
  - `Steam>` 已出现
  - `login 用户名 密码` 命令已真实发出
  - 失败点不是命令格式，也不是发送时机
- 曾经存在“启动前同步清理逻辑阻塞 SteamCMD 控制台启动”的问题，后已移除该阻塞逻辑。
- 曾出现 `steamcmd` / `steamcmd.sh` 残留孤儿进程，后来已增加退出时子进程组清理。
- 旧的“浏览页进入即额外 `refresh()`”曾导致重复刷新，现已移除。

## Notes For Future Updates
- 若 Steam 路由、工具栏、菜单、焦点、通知中转任一协作关系变化，需同步更新：
  - `docs/framework-architecture-memo.md`
- 若只是新增一次实验、抓取样本或排障结论，不要继续把本文件写成日志流；应优先整理为：
  - 当前事实
  - 历史结论
  - 待确认问题
