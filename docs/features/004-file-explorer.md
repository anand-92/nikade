# FEAT-004: 文件浏览器

> 状态：✅ Done | 创建日期：2025-12-20 | 完成日期：2026-03-10

---

## 1. 功能概述

NSOutlineView 驱动的文件树 + 模糊搜索 Quick Open + 文件预览 + Git 状态标注 + 文件操作（复制/剪切/粘贴/删除/重命名）。

## 2. 用户流程

### 文件树
1. 项目切换时自动扫描（浅扫描 ~1ms，后台全量扫描带 gitignore）
2. 目录按需展开（lazy scan），避免初始加载大型项目卡顿
3. 文件名旁显示 Git 状态标记（A/M/D/R/U），目录继承最高优先级子文件状态

### Quick Open
1. Cmd+P 打开搜索面板
2. 输入关键字，模糊匹配文件名（支持路径回退搜索）
3. 方向键选择，Enter 打开文件

### 文件操作
- Cmd+C 复制 / Cmd+X 剪切 / Cmd+V 粘贴
- Delete 移入废纸篓
- 右键重命名

## 3. 技术实现

### 3.1 数据结构

```swift
struct FileExplorerNode: Identifiable, Hashable {
    let id: String      // 绝对路径
    let url: URL
    let name: String
    let isDirectory: Bool
    let gitState: FileGitState?
    let children: [FileExplorerNode]?  // nil = 未扫描（lazy）
}
```

### 3.2 扫描策略

1. **浅扫描**（maxDepth=1）: 项目打开时立即执行，展示顶层目录结构
2. **全量扫描**: 后台线程递归扫描，注入 gitignore + git status
3. **按需展开**: `expandDirectory()` 用户展开目录时单独扫描该目录
4. **缓存**: `projectScanCache` 按项目路径缓存，切换项目时即时恢复

### 3.3 Git 状态映射

```
classifyGitState: GitFileChange → FileGitState
  U → conflicted | D → deleted | R/C → renamed
  A/?/untracked → added | M/T → modified
```

目录状态 = `mergeGitState` 递归合并子文件状态（取最高优先级）。

### 3.4 模糊搜索算法

`fuzzyMatch(name:path:query:)`:
1. 先对文件名做模糊匹配（字符按序出现即可）
2. 评分因子：精确匹配 +1000、前缀 +600、连续匹配 +8、词首 +12、早期位置 +10、深度惩罚 -3/层
3. 回退：文件名不匹配时尝试路径子串匹配（得分较低）
4. 返回 Top 50 结果

### 3.5 忽略规则

- **硬编码**: `.git`, `.DS_Store`, `.build`, `DerivedData`, `ghostty-resources`, `GhosttyKit.xcframework`
- **gitignore**: 通过 `git ls-files --others --ignored` 获取，压缩冗余前缀（`compactDirectoryPrefixes`）

## 4. 注意事项

- NSOutlineView 比 SwiftUI List 性能好得多（支持 10k+ 节点零卡顿）
- 文件预览限制 160KB，检测二进制文件（null byte 检测）
- 剪切操作通过 UserDefaults flag 标记，粘贴时判断是复制还是移动
- 目录树变更通过 FileWatcher 自动刷新

## 5. 相关需求

- [REQ-003: 文件浏览器](../requirements/REQ-003-file-explorer.md)

## 6. 更新记录

| 日期 | 说明 |
|------|------|
| 2026-03-16 | 创建文档 |
