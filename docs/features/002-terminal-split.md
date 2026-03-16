# FEAT-002: 终端分屏系统

> 状态：✅ Done | 创建日期：2025-12-01 | 完成日期：2026-03-10

---

## 1. 功能概述

多标签 + 二叉树分屏终端系统。每个标签页包含一棵 `TerminalSplitNode` 树，支持水平/垂直分屏、拖拽调整比例、四方向焦点导航、窗格拖拽重排。

## 2. 用户流程

1. **新建标签**: Cmd+T 创建新终端标签（按项目自动编号 "Tab 1", "Tab 2"）
2. **分屏**: Cmd+D 水平分屏 / Cmd+Shift+D 垂直分屏
3. **切换焦点**: Cmd+Option+方向键 在窗格间导航
4. **调整大小**: 拖拽分割线，双击分割线均分所有窗格
5. **关闭窗格**: Cmd+W 关闭当前窗格（最后一个窗格时关闭标签）
6. **交换窗格**: 拖拽窗格到另一个窗格的边缘区域（左/右/上/下/中心）

## 3. 技术实现

### 3.1 数据结构

```swift
indirect enum TerminalSplitNode: Equatable {
    case leaf(UUID)                    // 单个终端窗格
    case split(axis, ratio, first, second) // 二叉分割
}
```

- `ratio` 范围 0.1–0.9（clamped），避免窗格被压缩到不可见
- `TerminalTabState` 持有 `splitTree` + `focusedPaneID`
- `TerminalWorkspaceStore` 管理所有标签 + 项目映射

### 3.2 渲染方式

采用 **flat 布局** 而非嵌套 View：`paneFrames(in:)` 递归计算每个 leaf 的绝对 CGRect，所有窗格用 `.frame()` + `.position()` 平铺在 GeometryReader 中。

优势：避免 SwiftUI 在树结构变更时销毁重建 NSView（会导致终端状态丢失）。

### 3.3 焦点导航

`nextPaneID(from:currentPaneID:frames:direction:)` 算法：
1. 过滤方向上的候选窗格（如 `.left` 只找 maxX ≤ 当前 minX 的窗格）
2. 多因子排序：距离 → 重叠度 → 横向偏移
3. 选择最优候选

### 3.4 窗格位置

每个 pane UUID 对应一个 `ghostty_surface_t`（由 GhosttyAppManager 管理）。

## 4. 注意事项

- 分割线宽度 1px，热区 8px（方便拖拽）
- 关闭窗格后焦点转移到最近的邻居（Euclidean 距离）
- 标签按项目隔离：切换项目只显示该项目的标签

## 5. 相关需求

- [REQ-001: 终端](../requirements/REQ-001-terminal.md)

## 6. 更新记录

| 日期 | 说明 |
|------|------|
| 2026-03-16 | 创建文档 |
