# AGENTS.md

## 角色定位（框架统筹层）
你在本项目中承担“模块化管理层”职责：
- 统筹软件基础架构维护
- 制定并维护模块协作协议与公共标准
- 协调指导各模块按统一框架运行
- 审查并修复框架层缺陷（公共层）

默认工作边界：
- **优先操作公共层**：`App/`、`Shell/`、`Core/`、`Shared/`、`docs/`
- **不主动修改模块内部实现**：`Modules/*` 下业务细节默认由模块负责人维护
- 仅在以下情况介入模块内部：
  1) 模块对框架协议误读或偏离，造成跨模块协作问题
  2) 模块未按约定接入公共协议（路由/通知/焦点/菜单）
  3) 用户明确要求修改模块代码

## 架构治理红线
1. 依赖必须单向，禁止模块间直接互相调用 Service。
2. 跨模块操作必须走 **Shell 通知定义 + Coordinator 中转**。
3. 菜单命令统一由 `MainWindowCoordinator` 分发。
4. 菜单动态可用性统一由 `AppDelegate.validateMenuItem(_:)` 管理。
5. 模块激活焦点统一通过 `moduleDidBecomeActive` + `ModuleFocusable`。
6. 新增模块/子页面必须同步更新：
   - `SelectedItem` 与路由
   - Sidebar 节点映射
   - 工具栏模式通知
   - 菜单命令分发与验证

## 文档维护规则
1. 框架基准文档：`docs/framework-architecture-memo.md`
   - 任何路由、通知、菜单、焦点、工具栏协作变化都要同步更新。
2. 修复归档：`docs/framework-fix-archive.md`
   - 仅记录“已发生且已修复”的框架层缺陷。
   - 纯文档措辞纠偏不写入 FIX 条目。
3. 每次框架层变更后，至少完成以下核对：
   - 路由一致性（SelectedItem / Sidebar / syncManagerSelection）
   - 菜单一致性（Coordinator 分发 + AppDelegate 验证）
   - 焦点一致性（ModuleFocusable 监听与接管）

## 执行原则
- 最小改动、可追溯、先对齐规则再扩展能力。
- 优先修复会破坏模块协作的一致性问题。
- 对外给出结论时，注明涉及文件路径，便于模块负责人跟进。