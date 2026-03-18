# Postmortem: NSOutlineView 列宽溢出导致 Git 角标不可见

**Date**: 2026-03-18
**Severity**: P2 (UI 功能异常，拖拽后可自愈)
**Resolution time**: 6 轮方案迭代
**影响范围**: FileExplorer — NSOutlineView 文件树

## Summary

从 ObservableObject + Combine 迁移到 @Observable 后，文件浏览器 NSOutlineView 的唯一列宽在初始加载时被撑到超过 scroll view 可见区域，导致 trailing anchor 定位的 git status 角标溢出到屏幕外。用户拖拽 sidebar 宽度后恢复正常，但首次加载必现。

## Root Cause

迁移到 @Observable 后，数据更新的时序发生了根本变化：

- **Combine 模式**: 通过 `$rootNodes.receive(on: RunLoop.main).sink` 订阅，数据更新在下一个 run loop tick 执行，此时 view 已完成布局，`autoresizesOutlineColumn` 能正确计算列宽
- **@Observable 模式**: SwiftUI 在渲染周期内同步调用 `updateNSViewController`，此时 view 可能还没有最终 frame

`autoresizesOutlineColumn = true` 的列宽调整逻辑在错误时机执行 —— 展开目录时列被撑宽，但因 frame 未确定，列无法收缩回可见区域。

## Timeline

### 发现

用户报告：文件浏览器展开目录后 git status 角标在屏幕外。仅首次加载时出现，拖拽 sidebar 宽度后恢复正常。

### 方案 1: viewDidLayout + sizeLastColumnToFit()

在 `OutlineTreeViewController.viewDidLayout` 中调用 `outlineView.sizeLastColumnToFit()`。

**结果**: ❌ 不工作。`sizeLastColumnToFit()` 只**扩展**不**收缩**，而问题恰好是列宽超过 clip view 需要收缩。

**副作用**: `viewDidLayout` 在每次 layout pass 都调用，导致更多视觉问题。

### 方案 2: viewDidLayout + column.width = scrollView.contentSize.width

直接设置列宽等于 scroll view 可见宽度。

**结果**: ❌ 更糟。`scrollView.contentSize.width` 在某些时机返回 0 或错误值，角标一直在屏幕外。用户回滚了此改动。

### 方案 3: autoresizingMask = [.width]

给 outlineView 设置 `autoresizingMask = [.width]` 让它跟随 clip view 宽度。

**结果**: ❌ 无效果。NSScrollView 的 documentView 管理机制不走 autoresizing mask。

### 方案 4: DispatchQueue.main.async { sizeLastColumnToFit() }

在 `updateData` 后异步调用 `sizeLastColumnToFit()`。

**结果**: ❌ 同方案 1，`sizeLastColumnToFit` 只扩展不收缩。

### 方案 5: DispatchQueue.main.async { column.width = scrollView.contentSize.width }

异步直接设列宽。

**结果**: ❌ `contentSize` 值仍然有问题，角标一直在屏幕外。

### 方案 6: diff main 分支找差异 ✅

对比 main 分支代码，发现根本差异：

| | main 分支 (Combine) | 当前分支 (@Observable) |
|---|---|---|
| 数据更新触发 | `$rootNodes.receive(on: RunLoop.main).sink` 异步 | `updateNSViewController` 同步调 `updateData` |
| reloadData 时机 | 下一个 run loop tick，view 已有正确 frame | 渲染周期内，frame 可能未确定 |
| autoresizesOutlineColumn | 展开时撑宽，异步更新时能收缩回来 | 展开时撑宽，同步更新时无法收缩 |

## Fix

三处改动：

1. **`autoresizesOutlineColumn = false`** — 阻止列在展开时自动撑宽，从根源消除问题
2. **`controller.rootNodes != store.rootNodes` 条件检查** — 避免 `syncData` 后的冗余 `reloadData`
3. **`refreshNow` 已有数据时用 `refreshFullOnly`** — 避免 shallow phase 替换完整树导致展开状态丢失

## Failed Approaches Summary

| # | 方案 | 失败原因 |
|---|------|---------|
| 1 | `viewDidLayout` + `sizeLastColumnToFit()` | API 只扩展不收缩；viewDidLayout 不适合一次性修复 |
| 2 | `column.width = scrollView.contentSize.width` | contentSize 在错误时机返回 0 或错误值 |
| 3 | `autoresizingMask = [.width]` | NSScrollView documentView 不走 autoresizing mask |
| 4 | async `sizeLastColumnToFit()` | 同方案 1，API 语义不变 |
| 5 | async `column.width = contentSize.width` | 同方案 2，contentSize 值仍不可靠 |

## Key Learnings

### 1. 迁移 ObservableObject → @Observable 时要注意时序变化

`updateNSViewController` 的执行时机和 Combine subscription 根本不同。Combine 的 `.receive(on: RunLoop.main)` 保证在下一个 run loop tick 执行，view 已完成布局；@Observable 的 `updateNSViewController` 在 SwiftUI 渲染周期内同步执行，AppKit 组件的 frame 可能还没确定。涉及 AppKit 桥接的场景必须逐个验证时序。

### 2. Apple API 语义陷阱: sizeLastColumnToFit()

名字暗示"调整列宽以适配可见区域"，实际语义是**只扩展不收缩**。使用 AppKit API 前应先查文档确认行为，不要从方法名推断。

### 3. 先 diff main 分支，再尝试修复

当问题在某个分支出现但 main 没有时，应该**第一时间** diff 找出分支差异，而不是靠猜测迭代修复方案。这个步骤本应在第 1 次尝试前就做，能省掉方案 1-5 的全部时间。

### 4. 避免 viewDidLayout 做一次性修复

`viewDidLayout` 在每次 layout pass 都调用，不适合做"初始化时修一次"的逻辑。在里面放副作用会导致不可预测的连锁反应。

## Files Changed

- `openOwl/Features/FileExplorer/OutlineTreeView.swift` — `autoresizesOutlineColumn = false`，条件检查避免冗余 reloadData
- `openOwl/Features/FileExplorer/FileExplorerStore.swift` — `refreshNow` 已有数据时用 `refreshFullOnly`
