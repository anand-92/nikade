# Postmortem 复盘记录

> 记录开发过程中遇到的重要 bug、踩坑经历和解决方案，供后续参考避免重复犯错。

---

## 状态说明

| 状态 | 说明 |
|------|------|
| 已完成 | 问题已修复，复盘已归档 |

## 文档列表

| 日期 | 标题 | 模块 | 链接 |
|------|------|------|------|
| 2026-03-15 | Quick Open 六连 Bug 修复 | Quick Open | [查看](2026-03-15-quick-open-arrow-keys.md) |
| 2026-03-16 | Terminal Copy/Paste 不工作 | Terminal / Ghostty | [查看](2026-03-16-clipboard.md) |
| 2026-03-18 | NSOutlineView 列宽溢出 | Git / FileExplorer | [查看](2026-03-18-outline-column-width.md) |
| 2026-03-18 | Terminal 搜索 overlay 事件阻挡 | Terminal / Search | [查看](2026-03-18-search-overlay-event-blocking.md) |
| 2026-03-18 | v1.0.2 三连修 | Deployment / Sidebar / Terminal | [查看](2026-03-18-v1.0.2-triple-fix.md) |
| 2026-03-19 | 切换项目导致终端 surface 被销毁 | Terminal / SwiftUI | [查看](2026-03-19-terminal-surface-destroyed-on-project-switch.md) |
| 2026-03-19 | 终端通知功能：重复造轮子的教训 | Terminal / Ghostty | [查看](2026-03-19-terminal-notification-reinventing-wheel.md) |

## 按模块分类

### Terminal / Ghostty
- 2026-03-16 — Copy/Paste 不工作（`performKeyEquivalent` 路由 + surface API 参数错误）
- 2026-03-18 — 搜索 overlay 事件阻挡（SwiftUI `.contentShape` 阻挡 NSView）
- 2026-03-19 — 切换项目终端 surface 被销毁（@Observable + ForEach 拆卸 NSViewRepresentable）
- 2026-03-19 — 终端通知重复造轮子（ghostty 原生 `notify-on-command-finish`）

### SwiftUI + AppKit 混合架构
- 2026-03-18 — v1.0.2 三连修（opacity(0) 不阻挡 AppKit 事件、onTapGesture 阻断 List selection）
- 2026-03-18 — NSOutlineView 列宽溢出
- 2026-03-19 — 切换项目终端 surface 被销毁（ForEach 意外释放 NSViewRepresentable）

### Quick Open
- 2026-03-15 — 六连 Bug 修复

## 反复出现的主题

1. **SwiftUI + AppKit 混合架构**是 bug 温床——`.opacity(0)` 不等于 `isHidden`、`performKeyEquivalent` 遍历全部 NSView、ForEach 可能意外拆卸 NSViewRepresentable
2. **先搜索后动手**——框架/库往往已有现成方案
3. **先加日志后分析**——对 SwiftUI 生命周期问题，静态分析效率极低

## 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-19 | 创建索引，收录全部 7 篇复盘 |
