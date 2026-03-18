# FEAT-006: 项目管理侧边栏

> 状态：✅ Done | 创建日期：2026-01-10 | 完成日期：2026-03-14

---

## 1. 功能概述

项目列表导航：添加/移除项目、切换活跃项目、Git Worktree 子项目管理、分支前缀自动检测。持久化到 `~/.openowl/openowl.json`。异常时显示 Claude 状态提醒卡片（读取官方 status RSS）。

## 2. 用户流程

1. **添加项目**: 点击 + 按钮打开文件夹选择器
2. **切换项目**: 点击项目名称，终端 / Git / 文件浏览器同步切换
3. **Worktree**: 在项目下创建 Git Worktree，显示为子项目
4. **移除项目**: 右键移除（只从列表移除，不删除文件）
5. **状态感知**: Claude 出现异常时弹出提醒卡片，可点击打开官方状态页或关闭忽略本次 incident

## 3. 技术实现

### 3.1 数据模型

```swift
struct ProjectItem: Identifiable, Hashable, Codable {
    let id: String           // UUID
    let path: String         // 标准化绝对路径
    var name: String         // 显示名（目录名）
    var worktreeOf: String?  // 父项目 ID（nil = 根项目）
    var worktreeBranch: String?
    var lastBranch: String?  // 最后已知分支
    var branchPrefix: String? // GitHub 用户名 / 自定义前缀
}
```

### 3.2 持久化

```json
// ~/.openowl/openowl.json
{
  "projects": [ ... ],
  "activeProjectId": "..."
}
```

- Pretty-printed + sorted keys，方便人工查看和调试
- Atomic 写入防止损坏
- 启动时从 UserDefaults 一次性迁移（旧版兼容）
- 路径验证: `isReasonableProjectPath()` 要求 ≥3 个路径组件
- 去重: `uniqued()` 基于标准化路径

### 3.3 Worktree 支持

```
ProjectStore
  ├── addWorktreeProject(parentID, path, branch)
  ├── removeWorktreeProject(id)  → 回退到父项目
  └── renameWorktreeProject(id, newBranch)

GitService
  ├── addWorktree(branch, dirName)  → ~/.openowl/workspace/projects/{name}/{slug}
  ├── listWorktrees()
  └── removeWorktree(path)
```

Worktree 目录统一存放在 `~/.openowl/workspace/projects/` 下。

### 3.4 分支前缀

`branchPrefix` 用于 `BranchNameGenerator` 生成分支名（如 `sanvi/calm-vale`）。
- 自动检测: 解析 `git remote get-url origin` 提取 GitHub 用户名
- 回退: `NSFullUserName()` 转小写去空格
- 缓存在 ProjectItem 上，persist 后不再重复检测

### 3.5 项目隔离

切换 `activeProjectID` 时触发全局状态同步：
- 终端：只显示该项目的标签
- Git：切换到该项目的仓库
- 文件浏览器：切换到该项目的目录

### 3.6 Claude 异常提醒卡片

- 位置：Sidebar 底部（仅异常时显示）
- 数据源：`https://status.claude.com/history.rss`
- 判定：存在未 `Resolved` incident 即显示异常（包括 `Monitoring`）
- 刷新：启动立即拉取，之后每 5 分钟轮询
- 容错：拉取失败时静默保留当前显示，等待下一次轮询
- 关闭行为：用户点 `x` 后忽略当前 incident，仅新 incident 再次弹出

## 4. 注意事项

- 项目列表按名称排序（worktree 跟随父项目）
- 折叠/展开状态存在内存中（`collapsedProjectIDs`），不持久化
- 删除根项目时同时移除所有子 worktree

## 5. 相关需求

- [REQ-006: Claude 状态 Sidebar 指示器](../requirements/REQ-006-claude-status-sidebar.md)

## 6. 更新记录

| 日期 | 说明 |
|------|------|
| 2026-03-16 | 创建文档 |
| 2026-03-18 | 新增 Claude 异常提醒卡片（RSS 轮询 + 可关闭忽略） |
