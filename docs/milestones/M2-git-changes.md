# M2: Git 变更管理

## 目标

实现 Git 变更面板，支持查看状态、Stage/Unstage、提交、Diff 查看。

## 任务

### T2.1 Git Service
- [ ] GitService.swift — Process 封装调用 git CLI
- [ ] git status 解析 (--porcelain=v1)
- [ ] git diff 获取 (staged / unstaged)
- [ ] git add / restore --staged / commit

### T2.2 Changes Panel
- [ ] SwiftUI List 展示 Staged / Modified / Untracked 分组
- [ ] 单文件 Stage/Unstage 按钮
- [ ] Stage All / Unstage All
- [ ] Commit message textarea + Cmd+Enter 提交

### T2.3 Diff View
- [ ] Unified diff 渲染（SwiftUI Text with attributed strings 或 NSTextView）
- [ ] 绿色加行 / 红色减行高亮
- [ ] 文件头信息展示

### T2.4 文件监听
- [ ] FSEvents 监听工作目录变化
- [ ] 防抖 (300ms) 自动刷新 git status
- [ ] 忽略 .git/ 等目录

## 完成标准

- 侧边栏能看到文件变更列表
- 能 Stage/Unstage 文件并提交
- 能查看文件 diff
