# Project Working Memory

## Product Context
- `MyWallpaperX` 是一个 macOS 动态壁纸软件。
- Steam 创意工坊能力是软件中的一个工具型模块，不是产品唯一核心。
- Steam 这条链路的目标不是做完整 Steam 平台，而是：
  - 浏览 Wallpaper Engine 创意工坊里的视频类壁纸
  - 登录 Steam
  - 保持登录状态
  - 下载到 `~/Movies/MyWallpaperX/创意工坊`

## User Preferences
- 每次提问时，除非用户明确要求“直接改”，否则先检查、给结论，再等用户确认是否修改。
- 如果用户的建议不合理，需要主动指出并讨论，不要盲从。
- 优先做“最方便、最好用”的方案，而不是理论上最完美但工程代价过大的方案。
- 用户不希望用内嵌网页方式展示创意工坊浏览页，希望原生网格 UI。
- 登录页需要客户端化、流程直观。
- 登录状态和网格缓存都要持久化，不能每次返回都丢。

## Architecture Boundary
- 按 `AGENTS.md`，默认优先操作公共层：`App/`、`Shell/`、`Core/`、`Shared/`、`docs/`
- 这次 Steam 创意工坊功能属于用户明确要求修改的模块，可以进入 `Modules/SteamWorkshop`

## Current Steam Workshop Design
- 浏览页是原生网格，不直接呈现网页。
- 卡片默认展示较少信息。
- 点卡片进入类似 Quick Look 的详情弹窗。
- 详情弹窗内展示更多信息并提供下载按钮。
- 目前数据来源是抓取 Wallpaper Engine 创意工坊公开页面 HTML。

## Current SteamCMD Strategy
- 不放弃 SteamCMD。
- 当前采用“随 app 打包内置 SteamCMD 运行时”的方案。
- 当前链路是：
  - app
  - `/bin/bash`
  - `./steamcmd.sh`
- 下载和登录都仍然围绕 SteamCMD。
- `MyWallpaperXWallpaperDaemon` 现在只负责壁纸播放，不再承接 SteamCMD 登录/下载。

## Important Paths
- 项目根目录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX`
- 当前调试 app 构建产物：
  - `/Users/songziqiang/Library/Developer/Xcode/DerivedData/MyWallpaperX-ezuatvrxfeqxwzeubireydvbdhtc/Build/Products/Debug/MyWallpaperX.app`
- 新的 SteamCMD 认证日志路径：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 旧的容器日志路径：
  - `/Users/songziqiang/Library/Containers/com.songziqiang.MyWallpaperX/Data/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 当前 Steam Workshop 缓存目录：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop`
- SteamCMD 下载运行时目录：
  - `/Users/songziqiang/Library/Application Support/MyWallpaperX/SteamWorkshopRuntime`
- 下载目标目录：
  - `~/Movies/MyWallpaperX/创意工坊`

## Important Files
- Steam 服务实现：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift`
- Steam 浏览页：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopBrowserView.swift`
- Helper 可执行文件源码：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/WallpaperDaemonSources/main.swift`
- 框架备忘录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/docs/framework-architecture-memo.md`

## Confirmed Findings
- 旧版本在 App Sandbox 下运行时，SteamCMD 登录阶段会报：
  - `CreateBoundSocket: ::bind to port 0 returned error [no name available](1)`
- 旧日志里可以确认：
  - `Steam>` 已出现
  - `login 用户名 密码` 命令已真实发出
  - 失败点不是命令格式，也不是发送时机
- 后来把 helper 启动前加入了同步清理逻辑后，新的无沙盒版本出现了另一种问题：
  - helper 启动了
  - 但 `Steam>` 没有出现
  - 20 秒超时，提示“SteamCMD 控制台未进入可登录状态”
- 已判断启动前的同步清理逻辑会卡住 SteamCMD 控制台启动，已移除该阻塞逻辑。
- 失败时曾残留大量孤儿 `steamcmd` / `steamcmd.sh` 进程，导致 CPU 占用升高。
- 已增加退出时子进程组清理，避免再次大量残留。
- 旧的“浏览页进入即额外 `refresh()`”会导致重复刷新，已移除。

## Current Build Status
- 主 app 的 `ENABLE_APP_SANDBOX` 已改为 `NO`
- 最新 Debug 构建已成功编译
- SteamCMD 执行链路已从 daemon 切回主 app 直接启动内置 `steamcmd.sh`
- 当前需要验证：最新无沙盒构建下，直接启动链路是否稳定进入 `Steam>` 并保持登录/下载 UX 正常

## Current Risks
- SteamCMD 的实际运行行为对 macOS 权限模型很敏感。
- 现在不要再把 SteamCMD 逻辑重新塞回壁纸 daemon，避免职责再次混杂。
- 需要优先保证：
  - `steamcmd.sh` 能进入 `Steam>`
  - 登录命令能发送
  - 失败时能回收子进程
  - 进入浏览页时不再无意义触发重新登录

## Next Recommended Steps
- 用最新 Debug 构建重新测试一次登录。
- 第一优先级不是“马上登录成功”，而是确认是否已经恢复到：
  - `Steam>` 出现
  - `login ...` 被发送
- 若恢复到了这一步，再继续分析联网失败或 Steam Guard 流程。
- 每次分析时都优先读取最新日志，不凭记忆推断。

## How To Prompt Next Time
- 如果要我先接上下文：
  - “先读 `AGENTS.md`、`CLAUDE.md`、`docs/project-working-memory.md`、`docs/debug-logbook.md` 再继续。”
- 如果只想继续 Steam 问题：
  - “先读 `docs/project-working-memory.md` 和 `docs/debug-logbook.md`，继续处理 SteamCMD 登录问题。”
- 如果要我先看日志再判断：
  - “先读 `docs/project-working-memory.md`，再读取最新 Steam 日志给结论，不要直接改。”
- 多参考市面上主流软做法，不要自己盲目造轮子。
- 每次会话修改完记得修正本文档以免误导。
