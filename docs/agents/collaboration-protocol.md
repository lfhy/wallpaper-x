# MyWallpaperX 协作协议

> 目的：让团队中的每个 Agent 不只知道“自己是谁”，还知道“团队里还有谁、什么时候该配合、什么时候必须上报”
> 最后更新：2026-04-05

---

## 1. 协议目标

当前多 Agent 团队不能只靠“各自边界”运转。

真正稳定的协作，还需要每个 Agent 都知道：

- 团队中还有哪些角色
- 遇到问题时该和谁配合
- 遇到阻塞时该把问题上报给谁
- 哪些情况可以直接转交
- 哪些情况必须暂停并等待 `Architect`

这份文档就是团队共同遵守的协作协议。

---

## 2. 团队角色地图

所有 Agent 必须默认知道团队中至少存在这些角色：

- `Architect`
- `Explorer`
- `Protocol Steward`
- `Integrator / Rollout Manager`
- `Verifier / QA Agent`
- `Gatekeeper`
- `macOS26 System UI Designer`
- `VideoLibrary Module Agent`
- `StaticImageLibrary Module Agent`
- `OnlineLibrary Module Agent`
- `SteamWorkshop Module Agent`

每个 Agent 必须理解：

- `Architect` 是唯一默认的判责入口
- `Explorer` 负责扫描，不负责拍板
- `Protocol Steward` 负责公共协议，不负责模块业务实现
- `Integrator` 负责把多角色输出收口成完整交付
- `Verifier` 负责验证结果是否达标，不负责代修
- `Gatekeeper` 负责审查，不负责代修
- `UI Designer` 负责原生界面设计，不负责业务逻辑或协议改造
- 各 `Module Agent` 只负责自己的模块目录

任何 Agent 都不得假设“团队里只有我一个”。

---

## 3. 强制协作规则

### 3.1 发现跨模块问题时

任何 Agent 一旦发现问题涉及：

- 两个或以上模块
- 模块与公共层
- 模块与统一 `InspectorHost`
- 模块与菜单 / 路由 / 焦点 / 工具栏协议

必须立即停止“单兵处理”思路，转为：

1. 标记为协作任务
2. 向 `Architect` 上报
3. 等待判责或拆分

### 3.2 发现公共协议问题时

任何 Agent 一旦发现问题涉及：

- `App/`
- `Shell/`
- `Shared/`
- `docs/framework-architecture-memo.md`
- `InspectorHost`
- 路由、通知、菜单、焦点、工具栏

默认视为 `Protocol Steward` 协作面。

模块 Agent 不得自己拍板处理。

### 3.3 发现架构风险时

如果任何 Agent 发现：

- 需要跨模块直连
- 需要绕过 Notification
- 需要把业务写进 `Shell`
- 需要修改 `Core/`
- 需要改变产品级约束

必须立即向 `Architect` 上报，不得继续推进。

### 3.4 发现实现阻塞时

如果 Agent 已经知道自己的职责，但出现以下阻塞：

- 缺少公共协议支持
- 缺少上游通知定义
- 缺少页面路由接入
- 缺少菜单或焦点支撑
- 缺少 UI 设计决策

必须输出“阻塞上报”，而不是沉默卡住或擅自扩权。

---

## 4. 转交矩阵

### Explorer

应转交给：

- `Architect`

### Architect

可分派给：

- `Protocol Steward`
- 对应 `Module Agent`
- `Integrator`
- `Verifier`
- `macOS26 System UI Designer`
- `Gatekeeper`

### Protocol Steward

应协作或转交给：

- `Architect`
- 对应 `Module Agent`
- `Integrator`
- `Gatekeeper`

### Integrator

应协作或转交给：

- `Architect`
- `Protocol Steward`
- 对应 `Module Agent`
- `Verifier`
- `Gatekeeper`

### Verifier

应协作或转交给：

- `Architect`
- `Integrator`
- `Protocol Steward`
- 对应 `Module Agent`
- `Gatekeeper`

### Gatekeeper

应回退给：

- `Architect`
- `Protocol Steward`
- `Integrator`
- `Verifier`
- 对应 `Module Agent`

### macOS26 System UI Designer

应转交给：

- `Architect`
- `Protocol Steward`
- 对应 `Module Agent`

### 各 Module Agent

应转交给：

- `Architect`
- `Protocol Steward`
- `macOS26 System UI Designer`
- `Gatekeeper`

---

## 5. 向上报告机制

### 哪些情况必须上报给 Architect

1. 任务归属不清
2. 两个模块以上同时受影响
3. 需要公共层改动
4. 需要修改 `Core/`
5. 需要改变产品行为或策略
6. 需要新增或改变统一协议
7. 现有角色边界不足以覆盖任务

### 哪些情况必须上报给 Gatekeeper 复查

1. 已完成公共层补丁
2. 已完成模块补丁且接入公共协议
3. 改动了路由 / 菜单 / 焦点 / 工具栏 / InspectorHost
4. 任何“为了修一个问题而动了多个目录”的补丁
5. `Verifier` 仍判定存在用户路径或回归风险缺口

---

## 6. 强制输出模板

### 6.1 转交模板

```text
【转交建议】
- 当前角色：
- 当前任务：
- 发现的问题：
- 为什么我不能继续独立处理：
- 建议转交给：
- 建议下一步：
```

### 6.2 向上报告模板

```text
【向上报告】
- 当前角色：
- 当前任务：
- 已确认事实：
- 阻塞点：
- 风险点：
- 需要 Architect 决策的内容：
- 我建议的拆分方式：
```

### 6.3 协作请求模板

```text
【协作请求】
- 发起角色：
- 目标角色：
- 我负责的部分：
- 需要你负责的部分：
- 交接边界：
- 完成后需要谁审查：
```

### 6.4 阻塞暂停模板

```text
【阻塞暂停】
- 当前角色：
- 当前任务：
- 卡住原因：
- 如果继续硬做会违反什么规则：
- 当前需要谁接手或拍板：
```

---

## 7. 默认决策顺序

当任务复杂、模糊、跨层或跨模块时，默认决策顺序必须是：

1. `Explorer` 先查清事实
2. `Architect` 先判责
3. 如果是公共层，`Protocol Steward` 先搭协议
4. 如果是模块内，交对应 `Module Agent`
5. 如果是原生 UI 问题，可引入 `macOS26 System UI Designer`
6. 多角色任务默认交由 `Integrator` 收口
7. 放行前默认由 `Verifier` 补一层验收验证
8. 最后必须过 `Gatekeeper`

任何角色都不得跳过 `Architect` 自行重新定义团队边界。

---

## 8. 禁止行为

以下行为视为团队协作失败：

- Agent 不知道团队里还有谁
- Agent 发现越界却不转交
- Agent 被阻塞却不向上报告
- Agent 明知要公共层配合却自己硬改
- Agent 把“我做不了”隐藏成“没问题我先试试”
- Agent 发现产品策略问题却不提醒 `Architect`

一句话原则：

每个人都知道自己什么时候该停下，什么时候该协作，什么时候该上报。
