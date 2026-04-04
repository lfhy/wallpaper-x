# AGENTS.md

## 说明
本文件不是某个具体 Agent 的身份设定文件。

它的用途是说明：当前 `MyWallpaperX` 仓库里的机器人团队是怎么分工的、各自看哪些目录、什么事情该交给谁。

当前真正使用中的 `Architect` 入口文件是：

- `docs/agents/AGENTS.md`

当前真正使用中的其他 Agent 说明文件也都在：

- `docs/agents/`
- `MyWallpaperX/Modules/*/AGENTS.md`

---

## 当前机器人团队

当前团队由这些角色组成：

- `Architect`
- `Explorer`
- `Protocol Steward`
- `Gatekeeper`
- `macOS26 System UI Designer`
- `VideoLibrary Module Agent`
- `StaticImageLibrary Module Agent`
- `OnlineLibrary Module Agent`
- `SteamWorkshop Module Agent`

它们不是平级乱跑的自由 Agent，而是一套有职责边界的协作系统。

默认协作顺序：

`Explorer -> Architect -> Protocol Steward / Module Agent -> Gatekeeper`

如果任务是纯 UI 设计问题，可以在 Architect 判责后引入：

`macOS26 System UI Designer`

---

## 目录与职责分工

### 1. `docs/agents/`

这是机器人团队的主要配置目录。

主要职责：

- 放置 `Architect` 身份设定
- 放置 `Explorer`、`Gatekeeper`、`Protocol Steward`、`macOS26 UI Designer` 等公共角色说明
- 放置任务派发模板、审查清单、管理手册等辅助文档

当前大致分工：

- `docs/agents/AGENTS.md`
  - 当前实际使用中的 `Architect`
- `docs/agents/explorer/AGENTS.md`
  - 只读扫描、上下文构建、风险提示
- `docs/agents/protocol-steward/AGENTS.md`
  - 公共协议接入：路由、通知、菜单、工具栏、焦点、InspectorHost、文档同步
- `docs/agents/gatekeeper/AGENTS.md`
  - 审查与拒绝违规
- `docs/agents/macos26-ui-designer/AGENTS.md`
  - macOS 26 原生 UI 设计、界面层级、交互一致性

### 2. `MyWallpaperX/Modules/VideoLibrary/`

归属：

- `VideoLibrary Module Agent`

负责范围：

- 视频库内部功能
- `WallpaperManager` 相关模块内行为
- 视频列表、选择、排序、QuickLook、Inspector、播放链路相关模块实现

不负责：

- 直接修改其他模块
- 擅自改公共协议

### 3. `MyWallpaperX/Modules/StaticImageLibrary/`

归属：

- `StaticImageLibrary Module Agent`

负责范围：

- 图片库内部功能
- 图片标签系统
- 图片网格、选择、排序、QuickLook、Inspector

不负责：

- 直接设置视频壁纸链路
- 直接依赖其他模块 Service

### 4. `MyWallpaperX/Modules/OnlineLibrary/`

归属：

- `OnlineLibrary Module Agent`

负责范围：

- Pixabay 在线库浏览
- 已下载项页面
- 模块内搜索、下载、Bridge、QuickLook、Inspector

不负责：

- 直接调用 `WallpaperManager`
- 绕过通知中转触发播放

### 5. `MyWallpaperX/Modules/SteamWorkshop/`

归属：

- `SteamWorkshop Module Agent`

负责范围：

- Steam 创意工坊浏览
- 下载页
- 认证、下载、模块内工具栏、原生网格、Inspector

不负责：

- 直接调用视频库
- 擅自改变公共协议或产品级约束

### 6. `MyWallpaperX/App/`

默认归属：

- `Architect`
- `Protocol Steward`

负责范围：

- 菜单命令分发
- 菜单可用性校验
- 主窗口生命周期
- 框架级窗口行为

### 7. `MyWallpaperX/Shell/`

默认归属：

- `Architect`
- `Protocol Steward`

负责范围：

- 路由
- 侧边栏
- 主窗口框架
- 模块切换
- 焦点通知
- InspectorHost 宿主

红线：

- 不允许把业务逻辑塞进 `Shell`

### 8. `MyWallpaperX/Shared/`

默认归属：

- `Architect`
- `Protocol Steward`

负责范围：

- 公共 UI 原语
- 公共协议
- 公共交互桥接
- 通用宿主与适配器

红线：

- 不能放模块特定业务逻辑

### 9. `MyWallpaperX/Core/`

默认归属：

- 谨慎区域

说明：

- `Core/` 是敏感层
- 没有明确授权时，不应随意修改
- 即便是公共角色，也不能把它当成“顺手就能动”的目录

### 10. `docs/`

默认归属：

- `Architect`
- `Protocol Steward`
- `Gatekeeper`

负责范围：

- 架构备忘
- 修复归档
- Agent 说明体系
- 管理手册、审查清单、任务模板

---

## 这套团队当前遵守的核心规则

所有 Agent 默认都应遵守：

1. 禁止跨模块直接调用
2. 所有跨模块行为必须走 Notification
3. 不允许随意修改 `Core/` 或 `Shared/`
4. 不允许在 `Shell` 写业务逻辑
5. 所有修改必须使用 diff patch 输出
6. 修改必须是最小变更
7. 不确定职责时，先判责，不直接动手

---

## 什么时候该交给谁

### 交给 `Explorer`

当你还没搞清楚：

- 问题在哪
- 涉及哪些文件
- 会不会越界

### 交给 `Architect`

当你要先判断：

- 任务归谁
- 是否触达公共层
- 是否需要拆分给多个 Agent

### 交给 `Protocol Steward`

当任务涉及：

- 路由
- Notification
- 菜单
- 工具栏模式
- 焦点接管
- InspectorHost
- 文档同步

### 交给各 `Module Agent`

当任务明确是模块内部实现问题时：

- 视频库 -> `VideoLibrary Module Agent`
- 图片库 -> `StaticImageLibrary Module Agent`
- 在线库 -> `OnlineLibrary Module Agent`
- Steam -> `SteamWorkshop Module Agent`

### 交给 `macOS26 System UI Designer`

当任务主要是：

- 界面层级
- 排版与布局
- 工具栏、侧边栏、面板视觉一致性
- macOS 原生体验校正

但如果设计调整已经触达公共协议，仍需先经过 `Architect` 或 `Protocol Steward`。

### 交给 `Gatekeeper`

当补丁已经出来，需要审查：

- 是否越界
- 是否破坏架构
- 是否漏了文档同步
- 是否漏了菜单 / 焦点 / 路由 / InspectorHost 一致性

---

## 当前项目里的重要协作面

当前机器人团队在这个项目里，重点要认识这些公共协作面：

- 路由：`SelectedItem`、`DetailView`、`syncManagerSelection`
- 菜单：`MainWindowCoordinator` + `AppDelegate.validateMenuItem(_:)`
- 焦点：`moduleDidBecomeActive` + `ModuleFocusable`
- 工具栏：`VideoLibraryToolbarController` 统一主控
- 侧边栏：`SidebarViews`
- 跨模块播放中转：
  - `.onlineVideoReadyToPlay`
  - `.steamWorkshopVideoReadyToPlay`
- Inspector 统一详情宿主：
  - `InspectorHost`
  - `InspectorHostBridge`
  - `InspectorHostActions`

只要任务触达这些区域，就不该被当成“普通模块小改动”。

---

## 最后说明

如果以后角色继续扩展，这个文件只负责回答三件事：

1. 当前有哪些机器人角色
2. 它们各自主要看哪些目录
3. 出现一个任务时，大概该先找谁

它不负责承载某个具体 Agent 的详细身份设定。

详细角色规范，请到各自的 `AGENTS.md` 查看。
