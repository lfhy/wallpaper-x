# MyWallpaperX 审查清单

> 用途：我作为负责人，在代码进入实现或合入前，用统一清单检查机器人是否越界、漏项、破坏架构
> 最后更新：2026-04-03

---

## 1. 审查目标

我做审查，不只是看“能不能跑”，更重要的是看：

- 有没有越界
- 有没有破坏模块边界
- 有没有破坏公共协议
- 有没有把局部修复做成长期隐患

这份清单默认配合 `Gatekeeper` 使用；复杂任务还应结合 `Verifier` 的验收结论一起看。

---

## 2. 一级清单：先看是否直接拒绝

只要命中以下任一项，默认直接拒绝：

- 模块之间直接互相调用 Service
- 跨模块行为没有走 Notification
- 把业务逻辑写进 `Shell`
- 未经批准修改 `Core/`
- 未经批准修改 `Shared/`
- 明明是公共协议任务，却让模块 Agent 直接扩散修改
- 多角色任务没有经过 `Integrator` 收口
- 需要验证的交付没有经过 `Verifier`
- 没有 diff patch，只有口头说明
- 改了公共协议，却没同步 `docs/framework-architecture-memo.md`
- 改了统一 Inspector 宿主接入，却没同时检查宿主 / bridge / 模块内容三者关系

---

## 3. 二级清单：职责是否正确

### 3.1 Explorer

检查：

- 是否先读了 `docs/framework-architecture-memo.md`
- 是否明确列出涉及文件
- 是否明确列出涉及模块
- 是否列出通知 / 路由 / 菜单 / 焦点 / 工具栏触点
- 是否列出 Inspector / QuickLook / Feedback 触点
- 是否指出了可能越界点

拒绝信号：

- 只凭经验下结论
- 没扫描就建议修改
- 抢着给实现方案

### 3.2 Architect

检查：

- 是否明确判定任务归属
- 是否判断是否触达公共层
- 是否给出正确实施角色
- 是否指出禁止修改的层
- 是否要求最终经过 Gatekeeper

拒绝信号：

- 不拆任务
- 让一个 Agent 包办全部
- 模块与公共层混在一个实现建议里

### 3.3 Protocol Steward

检查：

- 是否只处理协议接入，而不是替模块写业务
- 是否覆盖了路由 / 通知 / 菜单 / 焦点 / 工具栏 / Inspector / 文档
- 是否把公共层变更写得最小
- 是否说明还需要哪个 Module Agent 对接

拒绝信号：

- 直接改模块业务逻辑
- 公共层改完不更新文档
- 让模块绕过 Coordinator

### 3.4 Module Agent

检查：

- 是否只改自己授权目录
- 是否没有顺手扩散到别的模块
- 是否没有直接依赖其他模块 Service
- 是否保持现有 Notification 中转边界
- 是否没有擅自改统一 InspectorHost 宿主协议
- 是否输出最小 diff patch

拒绝信号：

- 越目录修改
- 把公共层问题当模块问题硬做
- 为了方便直接接别的模块

### 3.5 Integrator

检查：

- 是否明确当前任务 owner
- 是否汇总了公共层补丁与模块补丁的拼装关系
- 是否指出还有哪些缺口未闭环
- 是否在进入放行前主动拉起 `Verifier`

拒绝信号：

- 把“大家都做了一点”误判成“任务已完成”
- 没有说明谁还要继续工作
- 没经过验证就直接送 Gatekeeper

### 3.6 Verifier

检查：

- 是否基于明确验收标准做验证
- 是否区分了已验证路径和未验证路径
- 是否明确指出阻塞放行的问题
- 是否把行为问题回退给正确角色

拒绝信号：

- 没有验收标准也宣布通过
- 只看代码，不看用户路径
- 发现问题后自己改实现而不回退

### 3.7 Gatekeeper

检查：

- 是否逐项检查架构红线
- 是否指出具体拒绝理由
- 是否要求补文档同步
- 是否检查菜单 / 路由 / 焦点 / 工具栏 / InspectorHost 一致性
- 是否结合了 `Verifier` 的验收结论做最终放行

拒绝信号：

- 模糊放行
- 只看功能，不看边界
- 对明显越界问题给“可优化”结论

---

## 4. 公共层专项清单

只要补丁涉及公共层，就必须检查以下内容。

### 4.1 路由一致性

检查：

- `SelectedItem` 是否同步
- `DetailView` 路由是否同步
- `syncManagerSelection` 是否同步
- 子页面是否正确归并到父模块

重点文件：

- `MyWallpaperX/Shell/ContentViewSupport.swift`
- `MyWallpaperX/Shell/ContentView.swift`

### 4.2 侧边栏一致性

检查：

- `SidebarSectionID` 是否同步
- `SidebarNodeKind` 是否同步
- `SidebarNode.selectedItem` 映射是否同步
- 节点计数是否进入 `SidebarSnapshotSignature`

重点文件：

- `MyWallpaperX/Shell/SidebarViews.swift`

### 4.3 菜单一致性

检查：

- `MainWindowCoordinator` 是否新增对应分发
- `AppDelegate.validateMenuItem(_:)` 是否新增对应校验
- 是否误把动态可用性写进 SwiftUI Commands

重点文件：

- `MyWallpaperX/App/MainWindowCoordinator.swift`
- `MyWallpaperX/App/AppDelegate.swift`

### 4.4 焦点一致性

检查：

- 是否仍通过 `moduleDidBecomeActive`
- 容器是否接入 `ModuleFocusable`
- 焦点是否给到正确的 `NSCollectionView` 或内部可交互视图

重点文件：

- `MyWallpaperX/Shared/UI/ModuleFocusable.swift`
- 各模块对应容器视图

### 4.5 工具栏一致性

检查：

- 是否仍由 `VideoLibraryToolbarController` 主控
- 子模块是否只是提供 item / 状态同步
- 是否有人直接 `removeItem` / `insertItem` 破坏主控原则

重点文件：

- `MyWallpaperX/Modules/VideoLibrary/Toolbar/VideoLibraryToolbarController.swift`
- 各模块 toolbar controller

### 4.6 Inspector 一致性

检查：

- 是否仍通过统一 `InspectorHost` 承载详情
- `InspectorHostBridge` 是否接在正确的模块入口视图上
- 模块是否只提供自己的 inspector 内容视图，不擅自改宿主协议
- `Inspector` / `QuickLook` / `Feedback` 三者语义是否仍分离
- 页面切换、选中清空、关闭详情时是否走统一关闭时序

重点文件：

- `MyWallpaperX/Shell/AppKitMainSplitView.swift`
- `MyWallpaperX/Shared/UI/InspectorHostBridge.swift`
- `MyWallpaperX/Shared/UI/InspectorHostActions.swift`
- 各模块对应 `*InspectorView.swift` / 入口视图

### 4.7 文档一致性

检查：

- 是否更新 `docs/framework-architecture-memo.md`
- 是否错误更新了 `docs/framework-fix-archive.md`

规则：

- 有真实框架变更：必须更新架构备忘录
- 有真实已修复框架缺陷：才写 fix archive
- 只是措辞修正：不写 fix archive

---

## 5. 模块专项清单

### 5.1 VideoLibrary

检查：

- 是否破坏 `WallpaperManager` 边界
- 是否让视频库直接依赖其他模块
- 是否影响导入上下文 `onlinePlayback` / `steamPlayback`
- 是否影响播放链路
- 是否破坏视频库 inspector 内容与选中态同步

### 5.2 StaticImageLibrary

检查：

- 是否保持图片标签系统独立
- 是否错误加入“设置动态壁纸”的旁路能力
- 是否影响 SIL 工具栏上下文
- 是否破坏图片库 inspector 内容与标签上下文关系

### 5.3 OnlineLibrary

检查：

- 是否仍通过 `.onlineVideoReadyToPlay` 中转到视频库
- 是否错误直接依赖 `WallpaperManager`
- 浏览页 / 已下载项页切换是否仍正确
- `OnlineDownloadsBridge` 是否仍只承担桥接职责
- 是否误把浏览页和已下载项页的 inspector 语义混在一起

### 5.4 SteamWorkshop

检查：

- 是否仍通过 `.steamWorkshopVideoReadyToPlay` 中转到视频库
- 是否错误直接依赖 `WallpaperManager`
- 是否擅自改变 steamcmd 运行策略
- 是否擅自扩展当前未接入的菜单能力
- 是否破坏 Steam inspector 内容与统一宿主的接入关系

---

## 6. 质量清单

除了架构，还要看实现质量。

检查：

- 是否最小变更
- 是否没有整文件重写
- 是否没有顺手修 unrelated 内容
- 是否命名与现有代码风格一致
- 是否补了必要注释，但没有写废话注释
- 是否避免引入新的隐式耦合

---

## 7. 我的标准审查结论

### 7.1 通过

适用：

- 归属正确
- 边界正确
- 公共协议同步完整
- patch 最小

输出建议：

```text
【Gatekeeper Verdict】
- 结论：PASS
- 审查范围：
- 放行理由：
- 仍需关注的低风险点：
```

### 7.2 拒绝

适用：

- 命中红线
- 越界修改
- 漏关键协议接入
- 漏文档同步

输出建议：

```text
【Gatekeeper Verdict】
- 结论：REJECT
- 发现的问题：
- 违反规则：
- 必改项：
- 应转交的 Agent：
```

### 7.3 需升级处理

适用：

- 涉及产品策略变化
- 涉及 `Core/` 或敏感公共层
- 涉及多个模块同时调整职责

输出建议：

```text
【Gatekeeper Verdict】
- 结论：NEEDS_ESCALATION
- 原因：
- 需要 Architect 重新决策的点：
- 当前补丁为何不能直接放行：
```

---

## 8. 最后的判断标准

我最终不是在问：

“它改完了吗？”

我在问：

- 它是不是由正确的人改的？
- 它是不是用正确的方式改的？
- 它有没有破坏未来继续协作的秩序？

如果答案不是肯定的，那这个补丁就不该通过。
