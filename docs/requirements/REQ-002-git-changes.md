# REQ-002: Git 变更管理

## 概述

简易 Git 管理面板，支持查看变更、Stage/Unstage、提交、查看 Diff。

## 核心需求

### P0 — 基础 Git 操作

- [ ] Git 状态获取：通过 `Process` 调用 `git status --porcelain=v1`
- [ ] 变更分组：Staged Changes / Changes (Modified) / Untracked
- [ ] Stage/Unstage：单文件和批量操作 (`git add` / `git restore --staged`)
- [ ] 提交：多行 commit message，Cmd+Enter 快捷键
- [ ] Auto-stage：如果没有 staged 文件，提交时自动 stage 所有变更

### P0 — Diff 视图

- [ ] Unified diff 渲染（绿色加/红色减）
- [ ] 点击文件展开 diff
- [ ] 文件内容预览（语法高亮）

### P1 — 分支管理

- [ ] 分支切换（dropdown selector）
- [ ] 创建/删除分支
- [ ] Pull / Push / Fetch
- [ ] Ahead/Behind 显示

### P2 — 增强

- [ ] AI commit message 生成（调用本地 claude CLI）
- [ ] Discard changes（with confirmation）

## 技术要点

### Git CLI 封装

```swift
class GitService {
    let workingDirectory: URL

    func status() async throws -> GitStatus { ... }
    func stage(files: [String]) async throws { ... }
    func commit(message: String) async throws { ... }
    func diff(file: String, staged: Bool) async throws -> String { ... }
}
```

通过 `Process` 执行 git 命令，解析 stdout 输出。比 libgit2 更简单可靠，支持所有 git 功能。

### 文件监听

使用 `DispatchSource.makeFileSystemObjectSource` 或 FSEvents API 监听工作目录变化，
自动刷新 git 状态。需忽略 `.git/`、`node_modules/` 等目录。
