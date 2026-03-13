# REQ-002: Git 变更管理

## 概述

简易 Git 管理面板，支持查看变更、Stage/Unstage、提交、查看 Diff。

## 核心需求

### P0 — 基础 Git 操作

- [x] Git 状态获取：通过 `Process` 调用 `git status --porcelain=v1`
- [x] 变更分组：Staged Changes / Changes (Modified) / Untracked
- [x] Stage/Unstage：单文件和批量操作 (`git add` / `git restore --staged`)
- [x] 提交：多行 commit message，Cmd+Enter 快捷键
- [x] Auto-stage：如果没有 staged 文件，提交时自动 stage 所有变更

### P0 — Diff 视图

- [x] Unified diff 渲染（绿色加/红色减）
- [x] 点击文件展开 diff
- [x] 文件内容预览（语法高亮）

### P1 — 分支管理

- [x] 分支切换（dropdown selector）
- [x] 创建/删除分支
- [x] Pull / Push / Fetch
- [x] Ahead/Behind 显示

### P2 — 增强

- [ ] AI commit message 生成（调用本地 claude CLI）
- [x] Discard changes（with confirmation）

## 技术要点

### Git CLI 封装

```swift
final class GitService {
    let workingDirectory: URL

    func status() async throws -> GitStatusSnapshot
    func stage(files: [String]) async throws
    func unstage(files: [String]) async throws
    func commit(message: String, autoStageWhenNeeded: Bool) async throws
    func diff(for change: GitFileChange) async throws -> String
    func branches() async throws -> [String]
    func checkout(branch: String) async throws
    func createBranch(name: String, checkout: Bool) async throws
    func deleteBranch(name: String, force: Bool) async throws
    func fetch() async throws
    func pull() async throws
    func push() async throws
}
```

通过 `Process` 执行 git 命令，解析 stdout/stderr 输出。继续维持 git CLI 路线，避免 libgit2 复杂度。

### 文件监听

当前使用 `FSEvents` 监听工作目录变化，
300ms 防抖后自动刷新 git 状态，并忽略 `.git/`、`node_modules/` 目录事件。

## 已落地实现

- `GitChangesView`：变更分组列表、Stage/Unstage、Stage All/Unstage All、Discard/Discard All（确认弹窗）、Diff 面板（含轻量语法高亮）、Commit 面板
- `GitChangesStore`：仓库选择、状态刷新、提交后回刷、branch create/delete/checkout、fetch/pull/push、discard、错误/提示状态管理
- `GitService`：新增 `discardModified` (`git restore --worktree`) 与 `discardUntracked` (`git clean -f -d`)
- `FileWatcher`：FSEvents 目录事件 -> 忽略规则过滤 -> 防抖刷新
- 侧边栏新增 `Git Changes` 面板入口
