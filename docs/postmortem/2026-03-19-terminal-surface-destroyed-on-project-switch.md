# 切换项目导致终端 surface 被销毁

> 日期：2026-03-19 | 影响：切换项目后终端重启，丢失命令历史和 shell 状态 | 定位耗时：长（静态分析兜圈子） → 加日志后秒定位

---

## 1. 问题

项目 A → B → A → B 切换后，项目 B 的终端会重启——出现全新 shell 提示符，命令历史丢失。用户原话："为什么切换项目 terminal 就重新载入了？"

## 2. 时间线

| 阶段 | 做了什么 | 结果 |
|------|---------|------|
| 1. 静态分析 | 反复阅读 ForEach + @Observable 交互代码，推测视图 identity 问题 | **浪费大量时间**，在 SwiftUI 生命周期猜测中兜圈子，无法确认根因 |
| 2. 加日志 | 在 `removeFromSuperview` 和 `viewDidMoveToWindow` 加 NSLog | **立即定位**——stack trace 暴露了完整调用链 |
| 3. 分析 stack trace | `NSView dealloc → _finalize → removeFromSuperviewWithoutNeedingDisplay` | TerminalScrollView 被 SwiftUI **释放**，dealloc 链带走了 TerminalNSView，进而释放 ghostty surface |
| 4. 修复 | GhosttyAppManager 持有强引用 + makeNSView 复用 | 终端不再重启 |
| 5. 后续问题 1 | 终端区域没填满，有边距 | ghostty 默认 2px padding → 配置 `window-padding-x/y = 0` |
| 6. 后续问题 2 | 拖拽后终端空白 | reattach 路径缺少 `ghostty_surface_set_focus(surface, true)` + `window.makeFirstResponder(self)` |

## 3. 根因

**SwiftUI @Observable + ForEach 交互导致 NSViewRepresentable 被意外拆卸。**

具体链条：

1. `tabs` 数组中某个元素的 `focusedPaneID` 发生变化
2. @Observable 将整个 `tabs` 属性标记为已变更
3. SwiftUI 对 ForEach 重新求值，尽管 `tab.id` 稳定，仍可能拆卸（dismantleNSViewRepresentable wrapper
4. 拆卸触发 TerminalScrollView 的 dealloc
5. dealloc 调用 `removeFromSuperviewWithoutNeedingDisplay` → TerminalNSView 随之释放 → ghostty surface 被销毁
6. 下次切换回来时只能创建新 surface → 全新 shell

## 4. 解决方案

| 改动 | 说明 |
|------|------|
| `GhosttyAppManager.retainedTerminalViews` | Manager 持有所有 TerminalNSView 的强引用，防止 SwiftUI 释放 |
| `removeFromSuperview` 不再释放 surface | 被移除视图层级 ≠ 被关闭，不触发 surface 清理 |
| `TerminalPanel.makeNSView` 复用 | 如果 Manager 中已有对应 pane 的 TerminalNSView，直接复用而非新建 |
| `destroyPane()` 显式清理 | tab 真正被关闭时调用，走 `destroyPaneHandler` 回调链到 GhosttyAppManager |
| ghostty 配置 `window-padding-x/y = 0` | 消除默认 2px 边距 |
| reattach 时恢复焦点 | `ghostty_surface_set_focus(surface, true)` + `window.makeFirstResponder(self)` |

## 5. 教训

### 核心教训：先加日志，后做分析

静态分析 SwiftUI 生命周期 bug 是**低效**的。SwiftUI 的 view identity、diffing、NSViewRepresentable 拆卸时机都是黑盒，纯靠代码阅读无法确认。

**正确流程：**
1. 在关键生命周期方法加 NSLog（`removeFromSuperview`、`viewDidMoveToWindow`、`deinit`）
2. 复现问题，拿到 stack trace
3. stack trace 会直接告诉你是谁在释放、从哪条路径触发

### 其他教训

- **@Observable 的"过度标脏"**：修改数组中一个元素的属性，整个数组属性都会被标记变更。ForEach 可能因此重建不应该重建的视图。
- **NSViewRepresentable 的生命周期不可控**：SwiftUI 可以在任何时候拆卸 NSViewRepresentable wrapper。对昂贵资源（终端 surface）必须在外部持有强引用。
- **"从视图层级移除" ≠ "用户关闭"**：`removeFromSuperview` 可能是 SwiftUI 的内部操作（重建、重排），不能在此释放业务资源。需要显式的 `destroy()` 方法区分两种场景。
