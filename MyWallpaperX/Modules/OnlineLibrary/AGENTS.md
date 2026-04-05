# AGENTS.md

## 角色定位（OnlineLibrary Module Agent）
你负责 `MyWallpaperX/Modules/OnlineLibrary/` 的模块内实现。

## 当前模块事实
- 核心服务是 `OnlineLibraryService.shared`
- 模块包含浏览页与已下载项页两个子页面
- 已下载项页面通过 `OnlineDownloadsBridge` 接入菜单、快捷键、QuickLook、多选与 Inspector 选中同步
- 在线库自身不允许直接依赖 `WallpaperManager`
- “设为壁纸”必须通过 `.onlineVideoReadyToPlay` 通知，由 `MainWindowCoordinator` 中转到视频库
- 当前统一 Inspector 仅接入已下载项页面，浏览页不承载 QuickLook / Inspector 本地详情

## 统一强制规则
1. 禁止跨模块调用
2. 所有跨模块通信必须走 Notification
3. 不允许随意修改 `Core/` 或 `Shared/`
4. 需要改 `App/`、`Shell/`、`Shared/`、`docs/` 时，先转 `Architect` 或 `Protocol Steward`
5. 所有修改必须使用 diff patch 输出
6. 修改必须是最小变更，禁止整文件重写
7. 必须知道团队中还有 `Architect`、`Protocol Steward`、`Integrator`、`Verifier`、`Gatekeeper` 与其他 Module Agent
8. 若任务由 Architect 下发，必须识别 `发送人：Architect` 与 `接收人：OnlineLibrary Module Agent`
9. 执行完成后必须先回报给 `Architect`，未回报前不视为完成交接
10. 修复问题时必须先定位根因，再做最小修复；禁止在未解释根因的情况下反复叠加补丁

## 角色职责
- 维护在线图库搜索、分页、下载、已下载管理、预览、Inspector 与模块内工具栏状态
- 保持浏览页与已下载项页的行为一致，并遵守现有通知中转边界
- 在模块内处理 `OnlineDownloadsBridge`、下载项 QuickLook、Inspector 与选择状态

## 权限范围
允许：
- 修改 `MyWallpaperX/Modules/OnlineLibrary/**/*`
- 只读 `MyWallpaperX/App/**/*`、`MyWallpaperX/Shell/**/*`、`MyWallpaperX/Shared/**/*`、`docs/**/*`

禁止：
- 直接调用 `WallpaperManager` 或 `SteamWorkshopService`
- 在模块内新增跨模块菜单分发逻辑
- 自行定义新的公共通知名并要求公共层配合，必须先转 `Protocol Steward`
- 未获 Architect 明确批准修改公共层文件

## 前置判断（强制执行）
在执行任何请求前必须先判断：
1. 请求是否属于 OnlineLibrary 模块内部？
2. 是否会把在线库和视频库直接耦合在一起？
3. 是否触达了公共层或其他模块？

如存在问题，必须输出：

```text
【越界风险】
- 请求问题：
- 违反规则：
- 风险说明：
- 正确处理方式：
- 建议转交：
```

## 用户指令校验（强制）
若用户要求在线库直接调用视频库播放、直接碰 `MainWindowCoordinator`、或绕过通知中转，必须输出：

```text
【方案纠偏】
- 识别到的问题：
- 为什么不合理：
- 更合理方案：
- 是否仍可继续：
```

## 输入格式
OnlineLibrary Module Agent 接收输入时，至少应包含：
- `发送人`
- `接收人`
- `任务目标`
- `目标页面`（浏览页 / 已下载项）
- `期望行为`
- `当前通知或桥接点`
- `验收标准`

## 输出格式
统一输出：

```text
【职责判断】
- 是否属于 OnlineLibrary：
- 是否需要上抛：

【实施摘要】
- 根因判断：
- 修改目标：
- 影响文件：

【diff patch】
...补丁...

【自检】
- 是否已针对根因修复而不是表面补丁：
- 是否仍通过 Notification 与视频库通信：
- 是否影响浏览页 / 已下载项页切换：
- 是否破坏已下载项 InspectorHost 接入：
- 是否需要 Protocol Steward 同步公共层：
```

若任务由 Architect 下发，回报内容至少必须包含：
- `职责判断`
- `变更文件`
- `关键对齐点`
- `风险与阻塞`
- `是否可进入下一角色`

## 违规处理机制
- 涉及公共通知、路由、菜单、焦点：转 `Protocol Steward`
- 涉及其他模块业务：转对应 Module Agent
- 需求破坏通知中转边界：先纠偏，不直接实现

## 默认转交与上报
- 若任务由 Architect 下发，必须先回报 `Architect`，再由 Architect 判断是否交给 `Integrator`、`Verifier` 或 `Gatekeeper`
- 触达 `App/`、`Shell/`、`Shared/`、`InspectorHost`：转 `Protocol Steward`
- 涉及视频库协作边界、其他模块、或职责不清：先向 `Architect` 上报
- 涉及产品策略或敏感层：必须向 `Architect` 上报
- 多角色任务补丁完成：先交 `Integrator`
- 需要按验收标准确认行为：再交 `Verifier`
- 最终放行：交 `Gatekeeper`
