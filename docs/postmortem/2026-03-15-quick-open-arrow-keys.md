# Quick Open 六连 Bug 修复复盘

日期: 2026-03-15
影响范围: Quick Open (Cmd+P) 面板
修复文件:
- `openOwl/Features/FileExplorer/QuickOpenSheet.swift`
- `openOwl/Features/FileExplorer/FileExplorerStore.swift`
- `openOwl/Features/FileExplorer/OutlineTreeView.swift`

## 概要

一次预计简单的 Quick Open 方向键修复，最终发现并修复了 6 个独立 bug。核心问题横跨 NSViewRepresentable 生命周期、SwiftUI view identity 机制、@Published 更新时序、以及 AppKit field editor 模型。最终方案是废弃 NSViewRepresentable，改用纯 SwiftUI 重写。

## Bug 清单

| # | 表面现象 | 根因 | 修复方式 |
|---|---------|------|---------|
| 1 | 方向键不工作 | AppKit field editor 拦截事件，NSTextField.keyDown 不触发 | 废弃 NSViewRepresentable，改用 SwiftUI TextField + `.onKeyPress` |
| 2 | 搜索不过滤（无高亮字符） | `.id(index)` 让 SwiftUI 用 index 做 view identity，数量不变时跳过内容刷新 | 改用 `.id(match.id)` |
| 3 | 搜索结果不刷新到 UI | SwiftUI `onChange` 内设置 `@Published` 触发嵌套 `objectWillChange`，被静默忽略 | Combine subscriber + `.receive(on: DispatchQueue.main)` 解耦 |
| 4 | 选中高亮消失 | 异步搜索结果数量变少，selectedIndex 越界 | `safeSelectedIndex` 计算属性 clamp |
| 5 | 切换项目搜索不准 | `dismissQuickOpen` 的 async 与 `presentQuickOpen` 竞态 | generation counter |
| 6 | Enter 打开文件但树不高亮 | selectNode 在 tab 切换前调用；Coordinator 不监听 `$selectedNodeID` | 先切 tab 再 async selectNode；添加 Combine 订阅 |

## 详细时间线

### Bug 1: 方向键不工作 — 7 个版本的迭代

**v1: NSTextField 子类 keyDown + 闭包** → 闭包捕获值类型快照，修改不回传

**v2: 隐藏 Button + .keyboardShortcut**（参考 CodeEdit）→ TextField 先消费方向键，Button 收不到

**v3: doCommandBy + Binding<Int>** → 搜索不过滤（暴露 Bug 2）

**v4: keyDown + Coordinator(Binding)** → 编辑模式下 keyDown 不触发（field editor 处理事件）

**v5: doCommandBy + onTextChange 回调** → 方向键双重触发（keyDown + doCommandBy 同时 fire）

**v6: 只用 doCommandBy** → 搜索结果仍不更新（暴露 Bug 3）

**v7 (最终): 纯 SwiftUI TextField + .onKeyPress** → 3 行代码解决

### Bug 2: `.id(index)` 陷阱

**调查过程:**
1. 怀疑 Binding<String> 链断裂 → 改用回调 → 无效
2. 怀疑 async debounce → 改为同步 → 无效
3. 怀疑 generation counter → 去掉 → 无效
4. **加日志** → 搜索逻辑完全正确: `query='.env' → 4 matches: [".env.example", ".env.local", ...]`
5. UI 仍显示旧数据 → 问题在 SwiftUI 渲染层

**根因:** `.id(index)` 让 SwiftUI 用 index (0,1,2,3) 做 view identity。结果数量从 4 变到另外 4 个文件时，index 不变，SwiftUI 跳过内容更新。

**修复:** `.id(match.id)` 用文件路径做 stable identity。

### Bug 3: objectWillChange 嵌套被静默忽略

`onChange` 内调 `updateQuickOpenResults()` → 设置 `@Published quickOpenResults` → 嵌套 `objectWillChange.send()` → SwiftUI 静默忽略。没有 warning、没有 crash。

**修复:** Combine subscriber + `.receive(on: DispatchQueue.main)` 在新 RunLoop 迭代中执行。

### Bug 4-6: 附带修复

- Bug 4: `safeSelectedIndex = min(selectedIndex, count - 1)` 防越界
- Bug 5: `presentQuickOpen` 递增 generation，让 pending dismiss block 失效
- Bug 6: 先切 tab 再 async `selectNode`；OutlineTreeView Coordinator 添加 `$selectedNodeID` 订阅

## 根因

核心失误：**选择了 NSViewRepresentable 方案来解决一个 SwiftUI 原生可以解决的问题。** `.onKeyPress`（macOS 14+）一行代码搞定方向键拦截，但因为参考了 CodeEdit 的旧方案（隐藏 Button + .keyboardShortcut），走了大量弯路。

次要失误：**理论推导代替加日志。** 连续 5 次理论分析都没命中根因（`.id(index)`），一行 print 语句立刻定位。

## 解决方案

最终方案是纯 SwiftUI：
```swift
TextField("Go to File", text: $store.quickOpenQuery)
    .focused($isSearchFocused)
    .onSubmit { openSelected() }
    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
    .onKeyPress(.escape) { store.dismissQuickOpen(); return .handled }
```

搜索触发用 Combine 解耦，避免 onChange 内设置 @Published：
```swift
querySubscription = $quickOpenQuery
    .dropFirst().removeDuplicates()
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.updateQuickOpenResults() }
```

## 教训

### 1. `.id(index)` 是最隐蔽的 SwiftUI bug
ForEach 的 `.id()` 必须用语义稳定的唯一标识符（如文件路径），永远不要用位置 index。SwiftUI 用 `.id()` 决定 view identity，index 不变就跳过内容更新。

### 2. onChange 内不能触发 @Published 更新
嵌套 objectWillChange 被静默忽略。用 Combine subscriber + `.receive(on:)` 解耦。

### 3. NSViewRepresentable 的复杂度不值得纯输入控件
SwiftUI 原生 API（`.onKeyPress`、`@FocusState`、`.onSubmit`）已足够。NSViewRepresentable 只在需要 AppKit 独有能力时使用。

### 4. 连续两次理论推导没命中时，立即加日志
理论分析花了大量时间，一行 print 立刻定位。

### 5. DispatchQueue.main.async 需要 generation guard
异步 block 的执行时机不可预测，dismiss → present 快速切换时必须防护。
