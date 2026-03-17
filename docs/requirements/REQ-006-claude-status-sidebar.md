# REQ-006: Claude 异常状态提醒

> 状态：✅ Done | 优先级：P1 | 预估工时：0.5天 | 创建日期：2026-03-18 | 完成日期：2026-03-18

---

## 1. 需求概述

当 Claude 出现未解决 incident 时，显示一个可关闭的异常提醒卡片；提醒关闭后忽略本次 incident，直到出现新的 incident 再显示。

## 2. 目标

- 用户不离开 openOwl，即可快速感知 Claude 当前是否异常
- 异常时可一眼看到正在进行中的 incident 标题
- 点击可快速跳转到官方状态页查看详情

## 3. 产品决策（已确认）

- **判定范围**：全站状态（不做 Claude Code 单独过滤）
- **异常规则**：只要存在未 `Resolved` 的 incident（包括 `Monitoring`）即视为异常
- **数据源**：仅 `history.rss`
- **刷新频率**：启动后立即拉取，之后每 5 分钟轮询
- **失败策略**：RSS 拉取失败时静默保留当前显示，不弹窗、不提示
- **展示方式**：仅异常时显示提醒卡片，非异常不常驻显示
- **忽略行为**：用户点击 `x` 后忽略当前 incident；新 incident 出现时重新显示
- **点击行为**：点击提醒中的链接打开状态页

## 4. UI 行为

异常提醒卡片（Sidebar 底部）：

```
⚠ Opus 4.6 Errors
Anthropic is reporting an active incident.
[Open status page]
```

用户关闭后：

```
本次 incident 不再提示
```

新的 incident 出现时：

```
再次显示提醒卡片
```

## 5. 技术方案

- 新增 `ClaudeStatusStore`（`@MainActor + @Observable`）：
  - 管理轮询任务
  - 拉取并解析 RSS
  - 输出 `checking/normal/abnormal` 状态和当前提醒 incident
  - 维护 dismissed incident 集合（按 incident key）
- RSS 解析：
  - 按 `item` 提取 `title/description/pubDate/link`
  - 从 `description` 中提取第一条 `<strong>...</strong>` 作为该 incident 最新状态
- 状态聚合：
  - `latestStatus != Resolved` 视为未解决
  - 若存在未解决项，状态为异常
  - 从未解决项中选出“未被 dismissed 的最新 incident”作为提醒内容
  - 若全部未解决项都已 dismissed，则不显示提醒，但状态仍为异常
  - 无未解决项则状态正常

## 6. 验收标准

- [x] 仅异常时显示提醒卡片
- [x] 点击提醒可打开 Claude 状态页
- [x] 点击 `x` 后当前 incident 不再重复提示
- [x] 新 incident 出现时可再次提示
- [x] RSS 拉取失败时不改变当前显示（静默）
- [x] 编译通过，现有功能无回归

## 7. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-18 | 初稿，锁定判定规则/刷新策略/失败策略 |
| 2026-03-18 | 完成实现与测试 |
| 2026-03-18 | 调整为“异常浮层提醒 + 可关闭 + 按 incident 忽略” |
